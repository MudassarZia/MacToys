import Foundation

public enum ToyError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public enum TextTransform: String, CaseIterable, Identifiable {
    case plain = "Plain text", json = "Format JSON", compactJSON = "Compact JSON"
    case csvJSON = "CSV → JSON", jsonCSV = "JSON → CSV", markdown = "CSV → Markdown"
    case htmlEscape = "Escape HTML", urlEncode = "URL encode", urlDecode = "URL decode"
    case base64 = "Base64 encode", unbase64 = "Base64 decode", upper = "UPPERCASE", lower = "lowercase"
    case trim = "Trim lines", sort = "Sort lines", unique = "Unique lines"
    public var id: String { rawValue }

    public func apply(_ text: String) throws -> String {
        switch self {
        case .plain: return text
        case .json, .compactJSON:
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
            var options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed]
            if self == .json { options.insert(.prettyPrinted) }
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: options), as: UTF8.self)
        case .csvJSON:
            let rows = try CSV.parse(text)
            guard let header = rows.first else { return "[]" }
            guard Set(header).count == header.count, !header.contains("") else { throw ToyError.message("CSV headers must be nonempty and unique.") }
            let objects = try rows.dropFirst().map { row -> [String: String] in
                guard row.count == header.count else { throw ToyError.message("Each CSV row must have \(header.count) columns.") }
                return Dictionary(uniqueKeysWithValues: zip(header, row))
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
        case .jsonCSV:
            guard let objects = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { throw ToyError.message("Expected a JSON array of objects.") }
            let keys = Set(objects.flatMap(\.keys)).sorted()
            guard !keys.isEmpty else { return "" }
            let rows = try objects.map { object in try keys.map { key -> String in
                guard let value = object[key], !(value is NSNull) else { return "" }
                if let string = value as? String { return string }
                return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
            } }
            return ([keys] + rows).map { $0.map(CSV.escape).joined(separator: ",") }.joined(separator: "\n")
        case .markdown:
            let rows = try CSV.parse(text)
            guard let header = rows.first else { return "" }
            guard rows.allSatisfy({ $0.count == header.count }) else { throw ToyError.message("CSV rows have different column counts.") }
            func line(_ row: [String]) -> String { "| " + row.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>") }.joined(separator: " | ") + " |" }
            return ([line(header), line(header.map { _ in "---" })] + rows.dropFirst().map(line)).joined(separator: "\n")
        case .htmlEscape: return text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
        case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? text
        case .urlDecode:
            guard let decoded = text.removingPercentEncoding else { throw ToyError.message("Invalid URL encoding.") }; return decoded
        case .base64: return Data(text.utf8).base64EncodedString()
        case .unbase64:
            guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), let result = String(data: data, encoding: .utf8) else { throw ToyError.message("Expected Base64 containing UTF-8 text.") }; return result
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .trim: return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        case .sort: return text.components(separatedBy: "\n").sorted().joined(separator: "\n")
        case .unique:
            var seen = Set<String>(); return text.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
        }
    }
}

public enum CSV {
    public static func escape(_ value: String) -> String {
        value.contains(",") || value.contains("\"") || value.contains("\r") || value.contains("\n") ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
    }
    public static func parse(_ text: String) throws -> [[String]] {
        if text.isEmpty { return [] }
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; closed = false }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = ""; closed = false }
            else if c == "\"" && field.isEmpty && !closed { quoted = true }
            else if c == "\"" || closed { throw ToyError.message("Malformed CSV near character \(i + 1).") }
            else { field.append(c) }
            i += 1
        }
        if quoted { throw ToyError.message("Unclosed CSV quote.") }
        if chars.last != "\n" { row.append(field); rows.append(row) }
        return rows
    }
}

public enum Shell {
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func environment(_ text: String) throws -> String {
        var result = ["#!/bin/zsh", "# Generated by MacToys. Source this file into the intended shell."]
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { throw ToyError.message("Line \(index+1): expected NAME=value.") }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw ToyError.message("Line \(index+1): invalid variable name.") }
            let value = String(line[line.index(after: eq)...])
            guard !value.contains("\0") else { throw ToyError.message("Null bytes are not supported.") }
            result.append("export \(key)=\(quote(value))")
        }
        return result.joined(separator: "\n") + "\n"
    }
}
