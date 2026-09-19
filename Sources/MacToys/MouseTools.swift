import AppKit
import SwiftUI

final class PointerOverlay: NSView {
    var pointer = CGPoint.zero
    var clicked = false
    var crosshair = true
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill()
        let color = NSColor.systemOrange
        color.withAlphaComponent(clicked ? 0.5 : 0.13).setFill()
        NSBezierPath(ovalIn: CGRect(x: pointer.x - 23, y: pointer.y - 23, width: 46, height: 46)).fill()
        color.withAlphaComponent(0.9).setStroke()
        let circle = NSBezierPath(ovalIn: CGRect(x: pointer.x - 23, y: pointer.y - 23, width: 46, height: 46)); circle.lineWidth = 2; circle.stroke()
        if crosshair {
            let path = NSBezierPath(); path.lineWidth = 1
            path.move(to: CGPoint(x: 0, y: pointer.y)); path.line(to: CGPoint(x: pointer.x - 26, y: pointer.y))
            path.move(to: CGPoint(x: pointer.x + 26, y: pointer.y)); path.line(to: CGPoint(x: bounds.width, y: pointer.y))
            path.move(to: CGPoint(x: pointer.x, y: 0)); path.line(to: CGPoint(x: pointer.x, y: pointer.y - 26))
            path.move(to: CGPoint(x: pointer.x, y: pointer.y + 26)); path.line(to: CGPoint(x: pointer.x, y: bounds.height)); path.stroke()
        }
    }
}
@MainActor final class MouseManager: ObservableObject {
    static let shared = MouseManager()
    @Published var active = false
    @Published var crosshair = true
    private var windows: [NSWindow] = []
    private var timer: Timer?
    func start() {
        stop()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.ignoresMouseEvents = true; window.level = .screenSaver; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.isReleasedWhenClosed = false
            window.contentView = PointerOverlay(frame: CGRect(origin: .zero, size: screen.frame.size)); window.orderFrontRegardless(); windows.append(window)
        }
        active = true
        timer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in Task { @MainActor in MouseManager.shared.update() } }
    }
    private func update() {
        let pointer = NSEvent.mouseLocation
        for window in windows {
            guard let view = window.contentView as? PointerOverlay else { continue }
            if window.frame.contains(pointer) { view.isHidden = false; view.pointer = CGPoint(x: pointer.x - window.frame.minX, y: pointer.y - window.frame.minY); view.clicked = NSEvent.pressedMouseButtons != 0; view.crosshair = crosshair; view.needsDisplay = true }
            else { view.isHidden = true }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; windows.forEach { $0.close() }; windows = []; active = false }
    func jump(_ screen: NSScreen) { let p = CGPoint(x: screen.frame.midX, y: Accessibility.desktopTop - screen.frame.midY); CGWarpMouseCursorPosition(p) }
}
struct MouseView: View {
    @ObservedObject private var manager = MouseManager.shared
    var body: some View {
        ToolPage(title: "Mouse Utilities", subtitle: "Make your pointer visible during demonstrations and jump between displays.") {
            Toggle("Show crosshairs", isOn: $manager.crosshair)
            Button(manager.active ? "Stop highlighting" : "Highlight pointer and clicks", systemImage: "cursorarrow.rays") { manager.active ? manager.stop() : manager.start() }.buttonStyle(.borderedProminent)
            Divider()
            Text("JUMP TO DISPLAY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in Button("\(index + 1). \(screen.localizedName)") { manager.jump(screen) } }
            Notice(text: "The ring brightens when a mouse button is held. Overlays ignore clicks and stop on quit. If your display arrangement changes, stop and restart highlighting. macOS already provides shake-to-find; it is not duplicated here.")
        }
    }
}

@MainActor final class DisplayManager: ObservableObject {
    static let shared = DisplayManager()
    @Published var amount = 0.0
    private var windows: [NSWindow] = []
    func update() {
        if amount == 0 { stop(); return }
        if windows.isEmpty {
            for screen in NSScreen.screens {
                let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isOpaque = false; window.backgroundColor = .black; window.hasShadow = false; window.ignoresMouseEvents = true; window.level = .statusBar; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.isReleasedWhenClosed = false; window.orderFrontRegardless(); windows.append(window)
            }
        }
        for window in windows { window.alphaValue = min(0.7, max(0, amount)) }
    }
    func stop() { windows.forEach { $0.close() }; windows = []; amount = 0 }
}
struct DisplayView: View {
    @ObservedObject private var manager = DisplayManager.shared
    var body: some View {
        ToolPage(title: "Display Shade", subtitle: "Software dimming for displays whose brightness keys don’t respond.") {
            HStack { Image(systemName: "sun.max"); Slider(value: $manager.amount, in: 0...0.7).onChange(of: manager.amount) { _, _ in manager.update() }; Text("\(Int(manager.amount * 100))% shade").monospacedDigit() }
            Button("Reset all displays") { manager.stop() }
            Notice(text: "This is a translucent overlay, not hardware brightness control. It does not reduce backlight power or change monitor contrast, input, volume, or color temperature. Hardware DDC/CI controls are not implemented. Shade is capped at 70%, never survives quit, and may appear in screenshots.")
        }
    }
}
