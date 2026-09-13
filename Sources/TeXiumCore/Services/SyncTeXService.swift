import Foundation

public struct PDFLocation: Equatable, Sendable {
    public let page: Int
    public let x: Double
    public let y: Double
    public init(page: Int, x: Double, y: Double) { self.page = page; self.x = x; self.y = y }
}
public struct SourceLocation: Equatable, Sendable {
    public let file: String
    public let line: Int
}
public enum SyncTeXService {
    public static func fields(_ output: String) -> [[String: String]] {
        var groups: [[String: String]] = []; var group: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]); let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if (key == "Output" || key == "Input") && group[key] != nil { groups.append(group); group = [:] }
            group[key] = value
        }
        if !group.isEmpty { groups.append(group) }
        return groups
    }
    public static func parseView(_ output: String) -> PDFLocation? {
        for group in fields(output) {
            if let p = group["Page"].flatMap(Int.init), let x = (group["x"] ?? group["h"]).flatMap(Double.init), let y = (group["y"] ?? group["v"]).flatMap(Double.init), p > 0 { return PDFLocation(page: p, x: x, y: y) }
        }
        return nil
    }
    public static func parseEdit(_ output: String) -> SourceLocation? {
        for group in fields(output) {
            if let file = group["Input"], let line = group["Line"].flatMap(Int.init), line > 0 { return SourceLocation(file: file, line: line) }
        }
        return nil
    }
    public static func forward(tool: URL, root: URL, file: String, line: Int, pdf: URL) async throws -> PDFLocation {
        let source = try ProjectFileSystem.resolve(file, in: root)
        let result = try await ProcessRunner().run(executable: tool, arguments: ["view", "-i", "\(line):0:\(source.path)", "-o", pdf.path], directory: root)
        guard result.status == 0, let location = parseView(result.output) else { throw TeXiumError.message("No SyncTeX location was found. Compile this source and try a line that appears in the PDF.") }
        return location
    }
    public static func inverse(tool: URL, root: URL, location: PDFLocation, pdf: URL) async throws -> SourceLocation {
        let result = try await ProcessRunner().run(executable: tool, arguments: ["edit", "-o", "\(location.page):\(location.x):\(location.y):\(pdf.path)"], directory: root)
        guard result.status == 0, let source = parseEdit(result.output) else { throw TeXiumError.message("No source location was found for this PDF position.") }
        let url = (source.file as NSString).isAbsolutePath ? URL(fileURLWithPath: source.file) : root.appendingPathComponent(source.file)
        return SourceLocation(file: try ProjectFileSystem.relative(url, to: root), line: source.line)
    }
}
