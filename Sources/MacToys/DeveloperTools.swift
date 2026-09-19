import SwiftUI
import AppKit
import MacToysCore

struct EnvironmentProfile: Codable, Identifiable { var id = UUID(); var name: String; var text: String }
struct EnvironmentView: View {
    @State private var profiles = Files.load([EnvironmentProfile].self, name: "environment") ?? [EnvironmentProfile(name: "Development", text: "# NAME=value (values are literal; no shell expansion)\nAPP_ENV=development\nPORT=3000\n")]
    @State private var selected = 0
    @State private var message = "Profiles are stored locally with owner-only file permissions. Use a password manager for secrets."
    var body: some View {
        ToolPage(title: "Environment Profiles", subtitle: "Group variables by project and export a safely quoted shell profile.") {
            HStack { Picker("Profile", selection: $selected) { ForEach(profiles.indices, id: \.self) { Text(profiles[$0].name).tag($0) } }; Button("New") { profiles.append(EnvironmentProfile(name: "New profile", text: "")); selected = profiles.count - 1 } }
            TextField("Profile name", text: $profiles[selected].name)
            Editor(text: $profiles[selected].text, height: 330)
            HStack {
                Button("Save profiles") { do { _ = try Shell.environment(profiles[selected].text); try Files.store(profiles, name: "environment"); message = "Profiles saved." } catch { message = error.localizedDescription } }
                Button("Export shell profile…") {
                    do { let script = try Shell.environment(profiles[selected].text); guard let url = Files.save(name: "environment.sh") else { return }; try Data(script.utf8).write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); message = "Exported. In your intended terminal run:\nsource \(Shell.quote(url.path))\nExisting apps and shells are unchanged." } catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
            Notice(text: message)
        }
    }
}

struct HostsView: View {
    @State private var text = ""
    @State private var original = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var message = "Read /etc/hosts, edit it, then review and save. Saving requests administrator authentication through macOS and creates a timestamped backup."
    @State private var confirm = false
    var body: some View {
        ToolPage(title: "Hosts Editor", subtitle: "Edit local hostname overrides with a backup before every save.") {
            HStack {
                Button("Read hosts file") { do { original = try String(contentsOfFile: "/etc/hosts", encoding: .utf8); text = original; loaded = true; message = "Loaded /etc/hosts." } catch { message = error.localizedDescription } }.disabled(busy)
                Button("Save with administrator approval…") { confirm = true }.buttonStyle(.borderedProminent).disabled(!loaded || text == original || busy)
                Button("Export a copy…") { guard let url = Files.save(name: "hosts.txt") else { return }; do { try text.write(to: url, atomically: true, encoding: .utf8); message = "Exported copy." } catch { message = error.localizedDescription } }
            }
            Editor(text: $text, height: 400).disabled(busy)
            Notice(text: message)
        }.confirmationDialog("Replace /etc/hosts with the edited text?", isPresented: $confirm) {
            Button("Back up and authenticate") { save() }
        }
    }
    func save() {
        guard !text.contains("\0") else { message = "Null bytes are not valid in a hosts file."; return }
        for (i, line) in text.components(separatedBy: .newlines).enumerated() {
            let body = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let parts = body.split(whereSeparator: \.isWhitespace)
            if parts.isEmpty { continue }
            var v4 = in_addr(), v6 = in6_addr()
            guard parts.count >= 2, inet_pton(AF_INET, String(parts[0]), &v4) == 1 || inet_pton(AF_INET6, String(parts[0]), &v6) == 1 else { message = "Line \(i + 1): expected an IPv4/IPv6 address followed by hostnames."; return }
        }
        let updated = text, base = original
        busy = true
        Task {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacToys-hosts-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory); busy = false }
            do {
                guard try String(contentsOfFile: "/etc/hosts", encoding: .utf8) == base else { throw ToyError.message("The hosts file changed since loading. Reload and reapply your edits.") }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let staged = directory.appendingPathComponent("hosts"), expected = directory.appendingPathComponent("original")
                try updated.write(to: staged, atomically: true, encoding: .utf8); try base.write(to: expected, atomically: true, encoding: .utf8)
                let backup = "/etc/hosts.mactoys-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).bak"
                let command = "/usr/bin/cmp -s /etc/hosts \(Shell.quote(expected.path)) || exit 75\n/bin/cp -p /etc/hosts \(Shell.quote(backup)) || exit 1\n/usr/bin/install -o root -g wheel -m 644 \(Shell.quote(staged.path)) /etc/hosts"
                let apple = "do shell script \"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\" with administrator privileges"
                let result = try await Runner.run("/usr/bin/osascript", ["-e", apple], timeout: 180)
                guard result.status == 0 else { throw ToyError.message(result.output.isEmpty ? "Save cancelled or failed." : result.output) }
                original = updated; message = "Saved. Backup: \(backup)\nDNS caches may take time to refresh."
            } catch { message = error.localizedDescription }
        }
    }
}

struct ShortcutItem: Identifiable { let id = UUID(); let title: String; let shortcut: String }
struct ShortcutsView: View {
    @State private var shortcuts: [ShortcutItem] = []
    @State private var message = "Switch to the app you want to inspect, return here, and click Read shortcuts."
    @State private var search = ""
    var body: some View {
        ToolPage(title: "Shortcut Guide", subtitle: "A searchable guide to the last active app’s menu shortcuts.") {
            HStack { Button("Read shortcuts", systemImage: "keyboard") { read() }.buttonStyle(.borderedProminent); TextField("Filter shortcuts", text: $search).textFieldStyle(.roundedBorder) }
            LazyVStack(alignment: .leading, spacing: 0) { ForEach(shortcuts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { item in HStack { Text(item.title); Spacer(); Text(item.shortcut).font(.system(.body, design: .monospaced)).foregroundStyle(Color.accentColor) }.padding(.vertical, 8); Divider() } }
            Notice(text: message)
        }
    }
    func read() {
        do {
            try Accessibility.require()
            guard let app = WindowManager.shared.previousApp, let raw = Accessibility.value(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute) else { throw ToyError.message("No accessible menu bar. Activate the target app first.") }
            var result: [ShortcutItem] = [], visited = 0
            func walk(_ element: AXUIElement, path: [String], depth: Int) {
                guard depth < 12, visited < 3000 else { return }; visited += 1
                let title = Accessibility.value(element, kAXTitleAttribute) as? String ?? ""
                if let key = Accessibility.value(element, kAXMenuItemCmdCharAttribute) as? String, !key.isEmpty {
                    let modifiers = (Accessibility.value(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
                    let keys = (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 1 != 0 ? "⇧" : "") + (modifiers & 8 == 0 ? "⌘" : "") + key.uppercased()
                    result.append(ShortcutItem(title: (path + [title]).filter { !$0.isEmpty }.joined(separator: " › "), shortcut: keys))
                }
                let next = title.isEmpty || path.last == title ? path : path + [title]
                for child in Accessibility.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(child, path: next, depth: depth + 1) }
            }
            walk(raw as! AXUIElement, path: [], depth: 0); shortcuts = result
            message = "\(result.count) menu shortcuts from \(app.localizedName ?? "app"). Context-only, dynamically populated, and non-menu shortcuts may not appear."
        } catch { message = error.localizedDescription }
    }
}

struct CommandHelpView: View {
    @State private var query = ""
    @State private var output = "Search installed Homebrew’s formula catalogue for a missing command. Searching can contact Homebrew; nothing is installed."
    @State private var busy = false
    var body: some View {
        ToolPage(title: "Command Not Found", subtitle: "Find a Homebrew package for a missing terminal command.") {
            HStack { TextField("Command or package name", text: $query).textFieldStyle(.roundedBorder); Button("Search Homebrew") { search() }.buttonStyle(.borderedProminent).disabled(busy || query.isEmpty) }
            Editor(text: $output, height: 350)
            Notice(text: "Optional shell integration is included in scripts/command-not-found.zsh in the source package. Install it yourself by sourcing that file in your .zshrc. It never installs packages automatically.")
        }
    }
    func search() {
        guard query.range(of: "^[A-Za-z0-9][A-Za-z0-9_.+-]{0,80}$", options: .regularExpression) != nil else { output = "Enter a simple command or package name."; return }
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { output = "Homebrew was not found at its standard installation paths. Install it separately from brew.sh if you want package suggestions."; return }
        let name = query; busy = true
        Task { do { let result = try await Runner.run(brew, ["search", "--formula", "--", name], timeout: 45); output = result.output.isEmpty ? "No formula matches found." : result.output } catch { output = error.localizedDescription }; busy = false }
    }
}
