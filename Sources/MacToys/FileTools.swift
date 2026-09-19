import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import MacToysCore

struct PasteView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var transform = TextTransform.json
    @State private var message = "Clipboard access happens only when you click Read clipboard. Nothing is sent online."
    var body: some View {
        ToolPage(title: "Advanced Paste", subtitle: "Make copied text fit the next task. Sixteen local transformations, no account required.") {
            HStack {
                Button("Read clipboard", systemImage: "clipboard") { input = NSPasteboard.general.string(forType: .string) ?? "" }
                Picker("Transform", selection: $transform) { ForEach(TextTransform.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 260)
                Button("Transform") { do { output = try transform.apply(input); message = "Ready to copy." } catch { output = ""; message = error.localizedDescription } }.buttonStyle(.borderedProminent)
            }
            Editor(text: $input).onChange(of: input) { _, _ in output = "" }
            HStack { Text("RESULT").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Button("Copy result", systemImage: "doc.on.doc") { Files.copy(output); message = "Copied." }.disabled(output.isEmpty) }
            Editor(text: $output)
            Notice(text: message)
        }
    }
}

struct RenameView: View {
    @State private var files: [URL] = []
    @State private var search = ""
    @State private var replacement = ""
    @State private var regex = false
    @State private var sensitive = true
    @State private var extensions = false
    @State private var plan: [RenameItem] = []
    @State private var undo: [RenameItem] = []
    @State private var message = "Choose files, preview every change, then apply. Existing files are never overwritten."
    @State private var confirm = false
    private func invalidate() { plan = [] }
    var body: some View {
        ToolPage(title: "Power Rename", subtitle: "Batch renaming with regular expressions, a full preview, and session undo.") {
            HStack { Button("Choose files…", systemImage: "doc.badge.plus") { files = Files.choose(multiple: true); invalidate() }; Text("\(files.count) selected").foregroundStyle(.secondary) }
            TextField("Find", text: $search).textFieldStyle(.roundedBorder).onChange(of: search) { _, _ in invalidate() }
            TextField("Replace with (regex groups: $1, $2)", text: $replacement).textFieldStyle(.roundedBorder).onChange(of: replacement) { _, _ in invalidate() }
            HStack { Toggle("Regular expression", isOn: $regex); Toggle("Case sensitive", isOn: $sensitive); Toggle("Include extension", isOn: $extensions) }.onChange(of: [regex, sensitive, extensions]) { _, _ in invalidate() }
            HStack {
                Button("Preview changes") { do { plan = try Renamer.plan(files: files, search: search, replacement: replacement, regex: regex, caseSensitive: sensitive, includeExtension: extensions); message = "\(plan.filter { $0.source != $0.destination }.count) filenames will change." } catch { plan = []; message = error.localizedDescription } }.disabled(files.isEmpty)
                Button("Apply renames") { confirm = true }.buttonStyle(.borderedProminent).disabled(!plan.contains { $0.source != $0.destination })
                Button("Undo last batch") { do { _ = try Renamer.execute(undo); files = undo.map(\.destination); undo = []; plan = []; message = "Batch undone." } catch { message = error.localizedDescription } }.disabled(undo.isEmpty)
            }
            if !plan.isEmpty {
                VStack(spacing: 0) { ForEach(plan) { item in HStack { Text(item.source.lastPathComponent); Spacer(); Image(systemName: "arrow.right").foregroundStyle(.secondary); Spacer(); Text(item.destination.lastPathComponent).foregroundStyle(item.source == item.destination ? .secondary : .primary) }.font(.system(.body, design: .monospaced)).padding(10); Divider() } }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
            Notice(text: message)
        }.confirmationDialog("Rename \(plan.filter { $0.source != $0.destination }.count) files?", isPresented: $confirm) {
            Button("Rename files") { do { undo = try Renamer.execute(plan); files = plan.map(\.destination); plan = []; message = "Renamed. Undo is available until the next batch or you leave this tool; moved or replaced files may prevent undo." } catch { message = error.localizedDescription } }
        }
    }
}

struct ResizeView: View {
    @State private var files: [URL] = []
    @State private var size = 1600
    @State private var format = "png"
    @State private var message = "Originals stay untouched. Output images are orientation-corrected, with the longest edge limited to your chosen size."
    @State private var busy = false
    var body: some View {
        ToolPage(title: "Image Resizer", subtitle: "Resize a whole batch into a folder. Preserve aspect ratio and keep every original.") {
            HStack { Button("Choose images…", systemImage: "photo.on.rectangle") { files = Files.choose(multiple: true, types: ["png", "jpg", "jpeg", "heic", "tiff", "webp", "gif"]) }; Text("\(files.count) images").foregroundStyle(.secondary) }
            HStack { Text("Maximum edge"); TextField("Pixels", value: $size, format: .number).frame(width: 100); Text("px"); Picker("Format", selection: $format) { Text("PNG").tag("png"); Text("JPEG").tag("jpg") }.frame(width: 180) }
            Button(busy ? "Resizing…" : "Resize into folder…") {
                guard let directory = Files.choose(directories: true).first else { return }
                let inputs = files, edge = size, ext = format
                busy = true
                Task {
                    let report = await Task.detached { () -> String in
                        var successes = 0, errors: [String] = []
                        for file in inputs {
                            do {
                                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw ToyError.message("Unsupported image") }
                                let name = file.deletingPathExtension().lastPathComponent + "-\(edge)"
                                var destination = directory.appendingPathComponent(name + "." + ext), suffix = 2
                                while FileManager.default.fileExists(atPath: destination.path) { destination = directory.appendingPathComponent(name + "-\(suffix)." + ext); suffix += 1 }
                                let data = NSMutableData()
                                guard let writer = CGImageDestinationCreateWithData(data, (ext == "png" ? UTType.png.identifier : UTType.jpeg.identifier) as CFString, 1, nil) else { throw ToyError.message("Cannot create image") }
                                CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                                guard CGImageDestinationFinalize(writer) else { throw ToyError.message("Encoding failed") }
                                try (data as Data).write(to: destination, options: .withoutOverwriting)
                                successes += 1
                            } catch { errors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                        }
                        return "Saved \(successes) image(s)." + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))
                    }.value
                    message = report; busy = false
                }
            }.buttonStyle(.borderedProminent).disabled(files.isEmpty || size < 1 || size > 16000 || busy)
            Notice(text: message)
            Notice(text: "Animated images export their first frame. JPEG does not preserve transparency; PNG does. Metadata is not copied.")
        }
    }
}

struct LocksmithView: View {
    @State private var result = "Select a file to inspect its open handles. No processes are terminated."
    @State private var busy = false
    var body: some View {
        ToolPage(title: "File Locksmith", subtitle: "Find which processes are holding a file open.") {
            Button(busy ? "Inspecting…" : "Inspect a file…", systemImage: "lock.doc") {
                guard let url = Files.choose().first else { return }; busy = true
                Task {
                    do {
                        let response = try await Runner.run("/usr/sbin/lsof", ["-nP", "--", url.path])
                        if response.status == 0 { result = response.output }
                        else if response.status == 1 && response.output.isEmpty { result = "No visible open handles for \(url.lastPathComponent). System and other-user processes may not be visible." }
                        else { result = "lsof exited \(response.status):\n\(response.output)" }
                    } catch { result = error.localizedDescription }; busy = false
                }
            }.disabled(busy)
            Editor(text: $result, height: 380)
        }
    }
}

struct FileTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var filename: String
    var content: String
    static let defaults = [FileTemplate(name: "Markdown note", filename: "Untitled.md", content: "# Untitled\n\n"), FileTemplate(name: "JSON document", filename: "data.json", content: "{\n  \n}\n"), FileTemplate(name: "Shell script", filename: "script.sh", content: "#!/bin/zsh\nset -euo pipefail\n\n"), FileTemplate(name: "HTML page", filename: "index.html", content: "<!doctype html>\n<html lang=\"en\">\n<head><meta charset=\"utf-8\"><title>Untitled</title></head>\n<body></body>\n</html>\n")]
}
struct TemplatesView: View {
    @State private var templates = Files.load([FileTemplate].self, name: "templates") ?? FileTemplate.defaults
    @State private var selected = 0
    @State private var message = "Create reusable text templates. Files are created only at the destination you select."
    var body: some View {
        ToolPage(title: "New from Template", subtitle: "Give new files a useful starting point.") {
            HStack {
                Picker("Template", selection: $selected) { ForEach(templates.indices, id: \.self) { Text(templates[$0].name).tag($0) } }
                Button("Add") { templates.append(FileTemplate(name: "Custom template", filename: "new.txt", content: "")); selected = templates.count - 1 }
                Button("Import text…") { if let url = Files.choose().first { do { let text = try String(contentsOf: url, encoding: .utf8); templates.append(FileTemplate(name: url.deletingPathExtension().lastPathComponent, filename: url.lastPathComponent, content: text)); selected = templates.count - 1 } catch { message = error.localizedDescription } } }
            }
            TextField("Template name", text: $templates[selected].name)
            TextField("Default filename", text: $templates[selected].filename)
            Editor(text: $templates[selected].content)
            HStack {
                Button("Save templates") { do { try Files.store(templates, name: "templates"); message = "Templates saved locally." } catch { message = error.localizedDescription } }
                Button("Create file…") { guard let url = Files.save(name: templates[selected].filename) else { return }; do { try Data(templates[selected].content.utf8).write(to: url, options: .withoutOverwriting); message = "Created \(url.path)." } catch { message = error.localizedDescription } }.buttonStyle(.borderedProminent)
            }
            Notice(text: message)
        }
    }
}
