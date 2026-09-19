import AppKit
import UniformTypeIdentifiers
import SwiftUI
import MacToysCore

enum Files {
    static func choose(multiple: Bool = false, directories: Bool = false, types: [String]? = nil) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        if let types { panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) } }
        return panel.runModal() == .OK ? panel.urls : []
    }
    static func save(name: String) -> URL? {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        return panel.runModal() == .OK ? panel.url : nil
    }
    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacToys", isDirectory: true)
    }
    static func store<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = support.appendingPathComponent(name + ".json")
        try JSONEncoder().encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: support.appendingPathComponent(name + ".json")) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct ProcessResult { let status: Int32; let output: String }
enum Runner {
    /// No shell interpolation. File-backed output avoids pipe-buffer deadlocks.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 30) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            defer { try? FileManager.default.removeItem(at: outputURL) }
            let handle = try FileHandle(forWritingTo: outputURL); defer { try? handle.close() }
            let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = args
            process.standardOutput = handle; process.standardError = handle
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            if process.isRunning {
                process.terminate()
                let grace = Date().addingTimeInterval(2)
                while process.isRunning && Date() < grace { try await Task.sleep(nanoseconds: 50_000_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw ToyError.message("The operation timed out.")
            }
            process.waitUntilExit()
            let data = try Data(contentsOf: outputURL)
            return ProcessResult(status: process.terminationStatus, output: String(decoding: data.prefix(2_000_000), as: UTF8.self))
        }.value
    }
}

struct Notice: View {
    let text: String
    var body: some View {
        if !text.isEmpty { Text(text).font(.callout).textSelection(.enabled).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)) }
    }
}
struct ToolPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    if !title.isEmpty { Text(title).font(.system(size: 30, weight: .bold, design: .rounded)) }
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                content
            }.padding(30).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
struct Editor: View {
    @Binding var text: String
    var height: CGFloat = 240
    var body: some View { TextEditor(text: $text).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden).padding(10).frame(height: height).background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary)) }
}
