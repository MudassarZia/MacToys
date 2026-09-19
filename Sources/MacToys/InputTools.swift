import SwiftUI
import AppKit
import Carbon
import IOKit.pwr_mgt
import ApplicationServices
import MacToysCore

@MainActor final class AwakeManager: ObservableObject {
    static let shared = AwakeManager()
    @Published var active = false
    @Published var message = "Sleep normally"
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?
    func start(minutes: Int, display: Bool) {
        stop()
        let type = display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "MacToys Awake" as CFString, &assertion)
        guard result == kIOReturnSuccess else { message = "Unable to create sleep assertion: \(result)"; return }
        active = true
        message = minutes == 0 ? "Awake until you stop or quit MacToys" : "Awake until \(Date().addingTimeInterval(Double(minutes * 60)).formatted(date: .omitted, time: .shortened))"
        if minutes > 0 { timer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { _ in Task { @MainActor in AwakeManager.shared.stop() } } }
    }
    func stop() { timer?.invalidate(); timer = nil; if active { IOPMAssertionRelease(assertion) }; active = false; message = "Sleep normally" }
}
struct AwakeView: View {
    @ObservedObject private var manager = AwakeManager.shared
    @State private var minutes = 60
    @State private var display = true
    var body: some View {
        ToolPage(title: "Awake", subtitle: "Keep a download, presentation, or long-running task awake without changing system settings.") {
            Image(systemName: manager.active ? "sun.max.fill" : "moon.zzz.fill").font(.system(size: 72)).foregroundStyle(Color.accentColor).padding(20)
            Picker("Duration", selection: $minutes) { Text("30 minutes").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120); Text("Until stopped").tag(0) }.frame(width: 260)
            Toggle("Keep the display awake too", isOn: $display)
            HStack { Button(manager.active ? "Restart timer" : "Keep awake") { manager.start(minutes: minutes, display: display) }.buttonStyle(.borderedProminent); if manager.active { Button("Stop") { manager.stop() } } }
            Notice(text: manager.message)
            Notice(text: "Lid close, manual sleep, and low-battery safeguards still apply. All assertions end when MacToys quits.")
        }
    }
}

struct KeyRule: Codable, Identifiable {
    var id = UUID()
    var from: UInt16
    var to: UInt16
    var modifiers: UInt64
    var outputModifiers: UInt64
}
@MainActor final class InputManager: ObservableObject {
    static let shared = InputManager()
    @Published var enabled = false
    @Published var grab = false
    @Published var rules = Files.load([KeyRule].self, name: "keys") ?? []
    @Published var message = "Enable only when needed. Control–Option–Escape is an emergency stop; Secure Input can prevent remapping."
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var dragged: AXUIElement?
    private var dragStart = CGPoint.zero
    private var frame = CGRect.zero
    private var resize = false
    private var activeMappings: [Int64: KeyRule] = [:]
    static let modifiers = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
    func start() {
        do { try Accessibility.require() } catch { message = error.localizedDescription; return }
        if enabled { return }
        let mask = [CGEventType.keyDown, .keyUp, .leftMouseDown, .leftMouseDragged, .leftMouseUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, _ in
            MainActor.assumeIsolated { InputManager.shared.handle(type, event) }
        }, userInfo: nil) else { message = "Could not install the event tap. Enable Accessibility and, if requested, Input Monitoring in System Settings, then restart MacToys."; return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true); enabled = true; message = "Input tools active. Emergency stop: Control–Option–Escape."
    }
    func stop() {
        // Release output keys so disabling a mapping cannot leave a held key behind.
        for rule in activeMappings.values {
            let release = CGEvent(keyboardEventSource: nil, virtualKey: rule.to, keyDown: false)
            release?.flags = CGEventFlags(rawValue: rule.outputModifiers); release?.setIntegerValueField(.eventSourceUserData, value: 0x4D5459); release?.post(tap: .cghidEventTap)
        }
        activeMappings = [:]
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; enabled = false; dragged = nil; message = "Input tools stopped."
    }
    func save() { do { try Files.store(rules, name: "keys") } catch { message = error.localizedDescription } }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { stop(); return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.eventSourceUserData) == 0x4D5459 { return Unmanaged.passUnretained(event) }
        let flags = event.flags.rawValue & Self.modifiers
        if type == .keyDown || type == .keyUp {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == 53 && flags == CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue { stop(); return nil }
            let rule: KeyRule?
            if type == .keyUp { rule = activeMappings.removeValue(forKey: code) }
            else { rule = activeMappings[code] ?? rules.first { Int64($0.from) == code && $0.modifiers == flags }; if let rule { activeMappings[code] = rule } }
            if let rule { event.setIntegerValueField(.keyboardEventKeycode, value: Int64(rule.to)); event.flags = CGEventFlags(rawValue: rule.outputModifiers | (event.flags.rawValue & ~Self.modifiers)); event.setIntegerValueField(.eventSourceUserData, value: 0x4D5459) }
        }
        if type == .leftMouseDown && grab && event.flags.contains([.maskControl, .maskAlternate]) {
            let point = event.location
            var element: AXUIElement?
            if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success, let element {
                let window: AXUIElement?
                if (Accessibility.value(element, kAXRoleAttribute) as? String) == kAXWindowRole { window = element }
                else { window = Accessibility.value(element, kAXWindowAttribute).map { $0 as! AXUIElement } }
                if let window, let rect = Accessibility.frame(window) { dragged = window; frame = rect; dragStart = point; resize = event.flags.contains(.maskShift); return nil }
            }
        }
        if type == .leftMouseDragged, let dragged {
            let dx = event.location.x - dragStart.x, dy = event.location.y - dragStart.y
            var rect = frame
            if resize { rect.size = CGSize(width: max(120, frame.width + dx), height: max(80, frame.height + dy)) }
            else { rect.origin = CGPoint(x: frame.minX + dx, y: frame.minY + dy) }
            do { try Accessibility.setFrame(dragged, rect) } catch { message = error.localizedDescription }
            return nil
        }
        if type == .leftMouseUp && dragged != nil { dragged = nil; return nil }
        return Unmanaged.passUnretained(event)
    }
}

struct KeyboardView: View {
    @ObservedObject private var manager = InputManager.shared
    @State private var from: UInt16 = 0
    @State private var to: UInt16 = 1
    @State private var mods: UInt64 = 0
    @State private var targetMods: UInt64 = 0
    static let keys: [(String, UInt16)] = [("A",0),("S",1),("D",2),("F",3),("H",4),("G",5),("Z",6),("X",7),("C",8),("V",9),("B",11),("Q",12),("W",13),("E",14),("R",15),("Y",16),("T",17),("1",18),("2",19),("3",20),("4",21),("6",22),("5",23),("9",25),("7",26),("8",28),("0",29),("O",31),("U",32),("I",34),("P",35),("Return",36),("L",37),("J",38),("K",40),("N",45),("M",46),("Tab",48),("Space",49),("Delete",51),("Escape",53),("F5",96),("F6",97),("F7",98),("F3",99),("F8",100),("F9",101),("F11",103),("F10",109),("F12",111),("F4",118),("F2",120),("F1",122),("Left",123),("Right",124),("Down",125),("Up",126)]
    var body: some View {
        ToolPage(title: "Keyboard Manager", subtitle: "Remap physical keys and shortcuts while MacToys is running.") {
            HStack { Button(manager.enabled ? "Disable input tools" : "Enable input tools") { manager.enabled ? manager.stop() : manager.start() }.buttonStyle(.borderedProminent); Text(manager.enabled ? "Active" : "Off").foregroundStyle(.secondary) }
            HStack { keyPicker("From", selection: $from); modPicker("Modifiers", selection: $mods); Image(systemName: "arrow.right"); keyPicker("To", selection: $to); modPicker("Modifiers", selection: $targetMods) }
            Button("Add mapping") {
                guard !(from == 53 && mods == CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue) else { manager.message = "The emergency stop shortcut cannot be remapped."; return }
                manager.rules.removeAll { $0.from == from && $0.modifiers == mods }; manager.rules.append(KeyRule(from: from, to: to, modifiers: mods, outputModifiers: targetMods)); manager.save()
            }.disabled(manager.enabled)
            ForEach(manager.rules) { rule in HStack { Text(label(rule.from, rule.modifiers) + " → " + label(rule.to, rule.outputModifiers)).font(.system(.body, design: .monospaced)); Spacer(); Button("Remove", role: .destructive) { manager.rules.removeAll { $0.id == rule.id }; manager.save() }.disabled(manager.enabled) } }
            Notice(text: manager.message)
            Notice(text: "Disable input tools before editing mappings. Physical key labels use the US keyboard layout. Modifier-only remaps are already available in macOS Keyboard settings. No typed text is recorded or stored.")
        }
    }
    func keyPicker(_ title: String, selection: Binding<UInt16>) -> some View { Picker(title, selection: selection) { ForEach(Self.keys, id: \.1) { Text($0.0).tag($0.1) } } }
    func modPicker(_ title: String, selection: Binding<UInt64>) -> some View { Picker(title, selection: selection) { Text("None").tag(UInt64(0)); Text("⌘").tag(CGEventFlags.maskCommand.rawValue); Text("⌃").tag(CGEventFlags.maskControl.rawValue); Text("⌥").tag(CGEventFlags.maskAlternate.rawValue); Text("⇧").tag(CGEventFlags.maskShift.rawValue); Text("⌘⇧").tag(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue); Text("⌃⌥").tag(CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue) } }
    func label(_ code: UInt16, _ flags: UInt64) -> String { (flags & CGEventFlags.maskControl.rawValue != 0 ? "⌃" : "") + (flags & CGEventFlags.maskAlternate.rawValue != 0 ? "⌥" : "") + (flags & CGEventFlags.maskShift.rawValue != 0 ? "⇧" : "") + (flags & CGEventFlags.maskCommand.rawValue != 0 ? "⌘" : "") + (Self.keys.first { $0.1 == code }?.0 ?? "\(code)") }
}
struct GrabView: View {
    @ObservedObject private var manager = InputManager.shared
    var body: some View {
        ToolPage(title: "Grab & Move", subtitle: "Move windows without hunting for the title bar.") {
            Label("Control + Option + drag anywhere to move", systemImage: "hand.draw").font(.title3)
            Label("Add Shift to resize from the bottom-right", systemImage: "arrow.up.left.and.arrow.down.right").font(.title3)
            Toggle("Enable grab gestures", isOn: $manager.grab)
            Button(manager.enabled ? "Stop input tools" : "Start input tools") { manager.enabled ? manager.stop() : manager.start() }.buttonStyle(.borderedProminent)
            Notice(text: manager.message)
            Notice(text: "Uses Accessibility. Some apps and fullscreen windows cannot be moved or resized. Gestures and remapping share one event tap; stopping input tools disables both.")
        }
    }
}

@MainActor final class Hotkeys {
    static let shared = Hotkeys()
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    func start() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID(); GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                let index = Int(id.id) - 1
                if index >= 0 && index < WindowManager.shared.zones.count { WindowManager.shared.apply(WindowManager.shared.zones[index]) }
            } }; return noErr
        }, 1, &type, nil, &handler)
        for (index, code) in [18,19,20,21,23,22,26,28,25].enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4D545953, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { WindowManager.shared.message = "Could not register Control–Option–\(index + 1); another app may own that shortcut. Zone buttons still work." }
        }
    }
    func stop() { refs.forEach { UnregisterEventHotKey($0) }; refs = []; if let handler { RemoveEventHandler(handler) }; handler = nil }
}
