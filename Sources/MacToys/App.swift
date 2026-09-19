import SwiftUI
import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case overview, awake, zones, workspaces, grab, mirror, paste, rename, resize, templates, locksmith, ocr, studio, mouse, keyboard, shortcuts, environment, hosts, command, display
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .awake: return "Awake"
        case .zones: return "Window Zones"
        case .workspaces: return "Workspaces"
        case .grab: return "Grab & Move"
        case .mirror: return "Floating Mirror"
        case .paste: return "Advanced Paste"
        case .rename: return "Power Rename"
        case .resize: return "Image Resizer"
        case .templates: return "New from Template"
        case .locksmith: return "File Locksmith"
        case .ocr: return "Text Extractor"
        case .studio: return "Screen Studio"
        case .mouse: return "Mouse Utilities"
        case .keyboard: return "Keyboard Manager"
        case .shortcuts: return "Shortcut Guide"
        case .environment: return "Environment Profiles"
        case .hosts: return "Hosts Editor"
        case .command: return "Command Not Found"
        case .display: return "Display Shade"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .awake: return "sun.max"
        case .zones: return "rectangle.split.3x1"
        case .workspaces: return "rectangle.3.group"
        case .grab: return "hand.draw"
        case .mirror: return "rectangle.on.rectangle"
        case .paste: return "clipboard"
        case .rename: return "character.cursor.ibeam"
        case .resize: return "photo.on.rectangle.angled"
        case .templates: return "doc.badge.plus"
        case .locksmith: return "lock.doc"
        case .ocr: return "text.viewfinder"
        case .studio: return "pencil.and.outline"
        case .mouse: return "cursorarrow.rays"
        case .keyboard: return "keyboard"
        case .shortcuts: return "command"
        case .environment: return "terminal"
        case .hosts: return "network"
        case .command: return "questionmark.square.dashed"
        case .display: return "display"
        }
    }
    var summary: String {
        switch self {
        case .awake: return "Stay awake for the task at hand."
        case .zones: return "A place for every window."
        case .workspaces: return "Bring your working layout back."
        case .grab: return "Grab a window anywhere."
        case .mirror: return "Keep the important part in view."
        case .paste: return "Copied text, in the right format."
        case .rename: return "A better name. For every file."
        case .resize: return "Big batches. Smaller images."
        case .templates: return "Skip the blank-page routine."
        case .locksmith: return "Find the process holding your file."
        case .ocr: return "If you can see it, extract its text."
        case .studio: return "Freeze, draw, zoom, measure."
        case .mouse: return "A pointer nobody can miss."
        case .keyboard: return "Make the keys work your way."
        case .shortcuts: return "Your app’s shortcuts, together."
        case .environment: return "Project variables, organized."
        case .hosts: return "Local hostname overrides."
        case .command: return "Find that missing command."
        case .display: return "An extra layer of display dimming."
        default: return "Small tools. A more capable Mac."
        }
    }
    static let groups: [(String, [Tool])] = [("WORKSPACE", [.awake, .zones, .workspaces, .grab, .mirror]), ("FILES & TEXT", [.paste, .rename, .resize, .templates, .locksmith, .ocr]), ("INTERACTION", [.studio, .mouse, .keyboard, .shortcuts, .display]), ("DEVELOPER", [.environment, .hosts, .command])]
}

@main struct MacToysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("MacToys", id: "main") { RootView().frame(minWidth: 980, minHeight: 700).tint(Color(red: 1, green: 0.48, blue: 0.25)).accentColor(Color(red: 1, green: 0.48, blue: 0.25)) }
            .defaultSize(width: 1180, height: 820)
            .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra("MacToys", systemImage: "square.stack.3d.up") {
            Button("Open MacToys") { delegate.openWindow() }
            Divider()
            Button("Keep awake for 1 hour") { AwakeManager.shared.start(minutes: 60, display: true) }
            Button("Stop keeping awake") { AwakeManager.shared.stop() }
            Button("Stop input tools") { InputManager.shared.stop() }
            Button("Stop pointer overlay") { MouseManager.shared.stop() }
            Button("Reset display shade") { DisplayManager.shared.stop() }
            Divider()
            Button("Quit MacToys") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = WindowManager.shared; Hotkeys.shared.start(); NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { openWindow() }; return true }
    func openWindow() { WindowNavigation.open?(); NSApp.activate(ignoringOtherApps: true) }
    func applicationWillTerminate(_ notification: Notification) { AwakeManager.shared.stop(); InputManager.shared.stop(); MouseManager.shared.stop(); DisplayManager.shared.stop(); Hotkeys.shared.stop() }
}
@MainActor enum WindowNavigation { static var open: (() -> Void)? }
struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var selection: Tool? = .overview
    @State private var search = ""
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) { Image(systemName: "square.stack.3d.up.fill").font(.title).foregroundStyle(Color.accentColor); VStack(alignment: .leading, spacing: 3) { Text("MacToys").font(.system(size: 23, weight: .bold, design: .rounded)); Text("A LITTLE MORE CAPABLE").font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary) } }.padding(20)
                List(selection: $selection) {
                    Label(Tool.overview.title, systemImage: Tool.overview.icon).tag(Tool.overview)
                    ForEach(Tool.groups, id: \.0) { group in
                        Section(group.0) { ForEach(group.1.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { tool in Label(tool.title, systemImage: tool.icon).tag(tool) } }
                    }
                }.listStyle(.sidebar).searchable(text: $search, placement: .sidebar, prompt: "Find a tool")
            }.navigationSplitViewColumnWidth(min: 230, ideal: 245)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView(selection: $selection)
                case .awake: AwakeView()
                case .zones: ZonesView()
                case .workspaces: WorkspacesView()
                case .grab: GrabView()
                case .mirror: MirrorView()
                case .paste: PasteView()
                case .rename: RenameView()
                case .resize: ResizeView()
                case .templates: TemplatesView()
                case .locksmith: LocksmithView()
                case .ocr: OCRView()
                case .studio: ScreenStudioView()
                case .mouse: MouseView()
                case .keyboard: KeyboardView()
                case .shortcuts: ShortcutsView()
                case .environment: EnvironmentView()
                case .hosts: HostsView()
                case .command: CommandHelpView()
                case .display: DisplayView()
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }.onAppear { WindowNavigation.open = { openWindow(id: "main") } }
    }
}
struct OverviewView: View {
    @Binding var selection: Tool?
    var body: some View {
        ToolPage(title: "", subtitle: "Useful extras for your Mac, together in one place. Inspired by PowerToys, built for macOS.") {
            ForEach(Tool.groups, id: \.0) { group in
                Text(group.0).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    ForEach(group.1) { tool in Button { selection = tool } label: { VStack(alignment: .leading, spacing: 12) { Image(systemName: tool.icon).font(.system(size: 23)).foregroundStyle(Color.accentColor); Text(tool.title).font(.headline); Text(tool.summary).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }.padding(18).frame(maxWidth: .infinity, minHeight: 135, alignment: .topLeading).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(.quaternary)) }.buttonStyle(.plain) }
                }
            }
            Notice(text: "Independent open-source alpha. Some tools provide a macOS adaptation rather than full PowerToys parity. Permissions are requested when needed. No analytics, accounts, or cloud AI.")
        }
    }
}
