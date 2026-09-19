import Foundation

public struct RenameItem: Identifiable {
    public var id: URL { source }
    public let source: URL
    public let destination: URL
    let sourceIdentity: FileIdentity?
    public init(source: URL, destination: URL) { self.source = source; self.destination = destination; self.sourceIdentity = FileIdentity.read(source) }
}

struct FileIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    static func read(_ url: URL) -> FileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value)
    }
}

public enum Renamer {
    public static func plan(files: [URL], search: String, replacement: String, regex: Bool, caseSensitive: Bool, includeExtension: Bool) throws -> [RenameItem] {
        guard !search.isEmpty else { throw ToyError.message("Enter a search expression.") }
        let expression = try NSRegularExpression(pattern: regex ? search : NSRegularExpression.escapedPattern(for: search), options: caseSensitive ? [] : .caseInsensitive)
        let template = regex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
        let items = files.map { file -> RenameItem in
            let original = includeExtension ? file.lastPathComponent : file.deletingPathExtension().lastPathComponent
            var name = expression.stringByReplacingMatches(in: original, range: NSRange(original.startIndex..., in: original), withTemplate: template)
            if !includeExtension && !file.pathExtension.isEmpty { name += "." + file.pathExtension }
            return RenameItem(source: file, destination: file.deletingLastPathComponent().appendingPathComponent(name))
        }
        try validate(items)
        return items
    }

    public static func validate(_ items: [RenameItem]) throws {
        var names = Set<String>()
        for item in items {
            let name = item.destination.lastPathComponent
            guard !name.isEmpty, name != ".", name != "..", !name.contains(":"), !name.contains("\0"), item.destination.deletingLastPathComponent().standardizedFileURL == item.source.deletingLastPathComponent().standardizedFileURL else { throw ToyError.message("A replacement creates an invalid filename or changes its folder.") }
            let key = item.destination.standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(key).inserted else { throw ToyError.message("Multiple files would become \(name).") }
            guard FileManager.default.fileExists(atPath: item.source.path) else { throw ToyError.message("Source no longer exists: \(item.source.lastPathComponent).") }
            guard let identity = item.sourceIdentity, identity == FileIdentity.read(item.source) else { throw ToyError.message("Source was replaced since the preview: \(item.source.lastPathComponent). Preview again before renaming.") }
            if item.source != item.destination && FileManager.default.fileExists(atPath: item.destination.path) {
                throw ToyError.message("Destination already exists: \(name). Rename cycles and case-only renames are intentionally rejected.")
            }
        }
    }

    /// Renames within each source directory, never overwrites; rolls back completed moves on failure.
    public static func execute(_ items: [RenameItem]) throws -> [RenameItem] {
        try validate(items)
        var completed: [RenameItem] = []
        do {
            for item in items where item.source != item.destination {
                try FileManager.default.moveItem(at: item.source, to: item.destination)
                completed.append(item)
            }
        } catch {
            var failures: [String] = []
            for item in completed.reversed() {
                do { try FileManager.default.moveItem(at: item.destination, to: item.source) }
                catch { failures.append("\(item.destination.path) → \(item.source.path)") }
            }
            if !failures.isEmpty { throw ToyError.message("Rename failed: \(error.localizedDescription). Rollback also failed for: \(failures.joined(separator: "; ")). Inspect these files before retrying.") }
            throw error
        }
        return completed.reversed().map { RenameItem(source: $0.destination, destination: $0.source) }
    }
}

public struct Zone: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(name: String, x: Double, y: Double, width: Double, height: Double) {
        self.name = name; self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var valid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.00001 && y + height <= 1.00001 }
    public static let defaults: [Zone] = [
        Zone(name: "Left third", x: 0, y: 0, width: 1/3, height: 1),
        Zone(name: "Center third", x: 1/3, y: 0, width: 1/3, height: 1),
        Zone(name: "Right third", x: 2/3, y: 0, width: 1/3, height: 1),
        Zone(name: "Wide center", x: 0.15, y: 0.05, width: 0.7, height: 0.9)
    ]
}
