import SwiftUI
import AppKit
import ApplicationServices
import MacToysCore

enum Accessibility {
    static func require() throws {
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            throw ToyError.message("Enable MacToys in System Settings → Privacy & Security → Accessibility, then retry. Restart MacToys if macOS requests it.")
        }
    }
    static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func focused(_ pid: pid_t) -> AXUIElement? {
        guard let value = value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        return (value as! AXUIElement)
    }
    static func windows(_ pid: pid_t) -> [AXUIElement] { value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), let s = value(window, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) throws {
        var point = frame.origin, size = frame.size
        let a = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        let b = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
        // Some apps re-position themselves while resizing. Repeat position after size settles.
        guard a == .success, b == .success else { throw ToyError.message("This window refused resizing or moving (AX \(a.rawValue), \(b.rawValue)). Fullscreen and fixed-size windows may not support zones.") }
    }
    static var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    static func axFrame(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height) }
}

@MainActor final class WindowManager: ObservableObject {
    static let shared = WindowManager()
    @Published var zones = Files.load([Zone].self, name: "zones") ?? Zone.defaults
    @Published var message = "Select a zone to move the last active app window. Global shortcuts: Control–Option–1 through 9."
    var previousApp: NSRunningApplication?
    private var observer: NSObjectProtocol?
    init() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousApp = nil }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.previousApp = app }
        }
        zones = zones.filter(\.valid)
        if zones.isEmpty { zones = Zone.defaults }
    }
    func apply(_ zone: Zone) {
        do {
            try Accessibility.require()
            let current = NSWorkspace.shared.frontmostApplication
            guard let app = current?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApp : current, let window = Accessibility.focused(app.processIdentifier), let frame = Accessibility.frame(window) else { throw ToyError.message("Switch to a normal app window first, then choose a zone.") }
            let screen = NSScreen.screens.max { a, b in
                let first = Accessibility.axFrame(a.frame).intersection(frame), second = Accessibility.axFrame(b.frame).intersection(frame)
                return (first.isNull ? 0 : first.width * first.height) < (second.isNull ? 0 : second.width * second.height)
            } ?? NSScreen.main!
            let bounds = Accessibility.axFrame(screen.visibleFrame), gap: CGFloat = 8
            let target = CGRect(x: bounds.minX + bounds.width * zone.x + gap/2, y: bounds.minY + bounds.height * zone.y + gap/2, width: bounds.width * zone.width - gap, height: bounds.height * zone.height - gap)
            try Accessibility.setFrame(window, target)
            message = "Moved \(app.localizedName ?? "window") to \(zone.name)."
        } catch { message = error.localizedDescription }
    }
    func save() { do { try Files.store(zones, name: "zones"); message = "Layout saved." } catch { message = error.localizedDescription } }
}

struct ZonesView: View {
    @ObservedObject private var manager = WindowManager.shared
    @State private var name = "Custom zone"
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var width = 50.0
    @State private var height = 100.0
    var body: some View {
        ToolPage(title: "Window Zones", subtitle: "Custom layouts beyond halves and quarters. Coordinates are percentages of the usable display.") {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.25))
                    ForEach(Array(manager.zones.enumerated()), id: \.element.id) { index, zone in
                        Button { manager.apply(zone) } label: { VStack { Text("\(index + 1)").font(.title2.bold()); Text(zone.name).font(.caption).lineLimit(1) }.frame(width: max(10, geometry.size.width * zone.width - 8), height: max(10, 200 * zone.height - 8)).background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5))) }.buttonStyle(.plain).offset(x: geometry.size.width * zone.x + 4, y: 200 * zone.y + 4)
                    }
                }
            }.frame(height: 200)
            ForEach(Array(manager.zones.enumerated()), id: \.element.id) { index, zone in
                HStack { Text(zone.name); Spacer(); if index < 9 { Text("⌃⌥\(index + 1)").foregroundStyle(.secondary) }; Button("Apply") { manager.apply(zone) }; Button("Remove", role: .destructive) { manager.zones.removeAll { $0.id == zone.id }; manager.save() } }
            }
            Divider()
            Text("ADD A ZONE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Name", text: $name)
            HStack {
                percent("Left", value: $x); percent("Top", value: $y); percent("Width", value: $width); percent("Height", value: $height)
            }
            Button("Add zone") {
                let zone = Zone(name: name, x: x/100, y: y/100, width: width/100, height: height/100)
                if zone.valid && width >= 5 && height >= 5 { manager.zones.append(zone); manager.save() }
                else { manager.message = "Use at least 5% width and height and keep the zone within 0–100%." }
            }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Notice(text: manager.message)
        }
    }
    func percent(_ label: String, value: Binding<Double>) -> some View { VStack(alignment: .leading) { Text(label).font(.caption); TextField(label, value: value, format: .number).textFieldStyle(.roundedBorder) } }
}

struct SavedWindow: Codable, Identifiable {
    var id = UUID()
    let bundleID: String
    let appName: String
    let title: String
    let index: Int
    let x: Double, y: Double, width: Double, height: Double
}
struct Workspace: Codable, Identifiable {
    var id = UUID()
    var name: String
    var windows: [SavedWindow]
}
struct WorkspacesView: View {
    @State private var workspaces = Files.load([Workspace].self, name: "workspaces") ?? []
    @State private var name = "My workspace"
    @State private var message = "Captures app identities, window titles, and positions locally. Does not save document contents or reopen closed documents."
    @State private var restoring = false
    var body: some View {
        ToolPage(title: "Workspaces", subtitle: "Bring your working layout back with one click.") {
            HStack { TextField("Workspace name", text: $name); Button("Capture layout", systemImage: "rectangle.3.group") { capture() }.disabled(restoring || name.isEmpty) }
            ForEach(workspaces) { workspace in
                GroupBox {
                    HStack { VStack(alignment: .leading, spacing: 6) { Text(workspace.name).font(.headline); Text("\(workspace.windows.count) windows · " + Set(workspace.windows.map(\.appName)).sorted().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Restore") { restore(workspace) }.disabled(restoring); Button("Delete", role: .destructive) { workspaces.removeAll { $0.id == workspace.id }; persist() }.disabled(restoring) }.padding(8)
                }
            }
            if workspaces.isEmpty { ContentUnavailableView("A place for every window", systemImage: "rectangle.3.group", description: Text("Arrange your apps, then capture your first workspace.")) }
            Notice(text: message)
        }
    }
    func persist() { do { try Files.store(workspaces, name: "workspaces") } catch { message = error.localizedDescription } }
    func capture() {
        do {
            try Accessibility.require()
            var windows: [SavedWindow] = []
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                guard let id = app.bundleIdentifier else { continue }
                for (index, window) in Accessibility.windows(app.processIdentifier).enumerated() {
                    guard let frame = Accessibility.frame(window), frame.width > 0, frame.height > 0 else { continue }
                    windows.append(SavedWindow(bundleID: id, appName: app.localizedName ?? id, title: Accessibility.value(window, kAXTitleAttribute) as? String ?? "", index: index, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
                }
            }
            guard !windows.isEmpty else { throw ToyError.message("No accessible app windows were found.") }
            workspaces.append(Workspace(name: name, windows: windows)); persist(); message = "Captured \(windows.count) windows."
        } catch { message = error.localizedDescription }
    }
    func restore(_ workspace: Workspace) {
        do { try Accessibility.require() } catch { message = error.localizedDescription; return }
        restoring = true
        Task { @MainActor in
            var restored = 0, errors: [String] = []
            for bundle in Set(workspace.windows.map(\.bundleID)).sorted() {
                do {
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { throw ToyError.message("App is not installed: \(bundle)") }
                    let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
                    let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    var live: [AXUIElement] = []
                    for _ in 0..<20 { live = Accessibility.windows(app.processIdentifier); if !live.isEmpty { break }; try await Task.sleep(nanoseconds: 250_000_000) }
                    var used = Set<Int>()
                    for saved in workspace.windows.filter({ $0.bundleID == bundle }) {
                        let exact = live.indices.first { !used.contains($0) && !saved.title.isEmpty && (Accessibility.value(live[$0], kAXTitleAttribute) as? String) == saved.title }
                        let index = exact ?? (live.indices.contains(saved.index) && !used.contains(saved.index) ? saved.index : nil)
                        guard let index else { errors.append("\(saved.appName): missing window “\(saved.title)”"); continue }
                        used.insert(index)
                        var rect = CGRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
                        let screens = NSScreen.screens.map { Accessibility.axFrame($0.visibleFrame) }
                        let screen = screens.max { a, b in
                            let ar = a.intersection(rect), br = b.intersection(rect)
                            return (ar.isNull ? 0 : ar.width * ar.height) < (br.isNull ? 0 : br.width * br.height)
                        } ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
                        rect.size.width = min(rect.width, screen.width); rect.size.height = min(rect.height, screen.height)
                        rect.origin.x = max(screen.minX, min(rect.minX, screen.maxX - rect.width)); rect.origin.y = max(screen.minY, min(rect.minY, screen.maxY - rect.height))
                        do { try Accessibility.setFrame(live[index], rect); restored += 1 } catch { errors.append("\(saved.appName): \(error.localizedDescription)") }
                    }
                } catch { errors.append(error.localizedDescription) }
            }
            message = "Restored \(restored) windows." + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n")); restoring = false
        }
    }
}
