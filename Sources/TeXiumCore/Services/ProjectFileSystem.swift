import Foundation
import CryptoKit

public struct TextFile: Sendable {
    public var text: String
    public let encoding: String.Encoding
    public let hasUTF8BOM: Bool
    public var baseline: Data
    public var lineEnding: String { text.contains("\r\n") ? "\r\n" : "\n" }
    public func encoded(_ value: String) throws -> Data {
        guard var data = value.data(using: encoding, allowLossyConversion: false) else {
            throw TeXiumError.message("The text cannot be represented in its original encoding. Save a UTF-8 copy instead.")
        }
        if hasUTF8BOM { data.insert(contentsOf: [0xef, 0xbb, 0xbf], at: 0) }
        return data
    }
}

public enum ProjectFileSystem {
    public static let hiddenNames: Set<String> = [".git", ".build", ".texium-build", ".texium", ".DS_Store"]
    public static let textExtensions: Set<String> = ["tex", "bib", "sty", "cls", "bst", "txt", "md", "csv", "tsv", "tikz", "ltx", "dtx", "ins", "cfg", "def"]

    public static func resolve(_ path: String, in root: URL) throws -> URL {
        guard !path.isEmpty, !(path as NSString).isAbsolutePath, !path.split(separator: "/").contains(".."), !path.contains("\0") else { throw TeXiumError.unsafePath(path) }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let url = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(base.path + "/") else { throw TeXiumError.unsafePath(path) }
        return url
    }
    public static func relative(_ url: URL, to root: URL) throws -> String {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard target.hasPrefix(base) else { throw TeXiumError.unsafePath(target) }
        return String(target.dropFirst(base.count))
    }
    public static func validateName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"), !name.contains("\0"), !name.contains("\n") else { throw TeXiumError.unsafePath(name) }
    }
    public static func tree(at root: URL) throws -> [ProjectFile] {
        func scan(_ directory: URL, prefix: String, depth: Int) throws -> [ProjectFile] {
            guard depth < 64 else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                .filter { !hiddenNames.contains($0.lastPathComponent) }
                .map { url in
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    let path = prefix + url.lastPathComponent
                    // Never recurse into symlinks (including cycles and paths outside the project).
                    let children = values.isDirectory == true && values.isSymbolicLink != true ? try scan(url, prefix: path + "/", depth: depth + 1) : nil
                    return ProjectFile(path: path, children: children)
                }.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return try scan(root, prefix: "", depth: 0)
    }
    public static func flatten(_ nodes: [ProjectFile]) -> [ProjectFile] {
        nodes.flatMap { [$0] + flatten($0.children ?? []) }
    }
    public static func read(_ url: URL) throws -> TextFile {
        let data = try Data(contentsOf: url)
        guard data.count <= 32 * 1024 * 1024 else { throw TeXiumError.message("This text file is larger than the editor’s 32 MB limit. Open it in an external editor.") }
        let bom = data.starts(with: [0xef, 0xbb, 0xbf])
        let body = bom ? Data(data.dropFirst(3)) : data
        let encodings: [String.Encoding] = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) ? [.utf16] : [.utf8]
        for encoding in encodings {
            if let text = String(data: body, encoding: encoding), !text.contains("\0") {
                return TextFile(text: text, encoding: encoding, hasUTF8BOM: bom, baseline: data)
            }
        }
        throw TeXiumError.message("\(url.lastPathComponent) is not UTF-8 or BOM-marked UTF-16 text. Convert a copy to UTF-8 before editing; the original file has been preserved.")
    }
    public static func save(_ text: String, file: TextFile, to url: URL) throws -> TextFile {
        let data = try file.encoded(text)
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                guard try Data(contentsOf: target) == file.baseline else { throw TeXiumError.conflict(target.lastPathComponent) }
                try data.write(to: target, options: .atomic)
            } catch { failure = error }
        }
        if let error = failure ?? coordinationError { throw error }
        return TextFile(text: text, encoding: file.encoding, hasUTF8BOM: file.hasUTF8BOM, baseline: data)
    }
    public static func mainDocument(in root: URL, files: [ProjectFile]) -> String? {
        let tex = flatten(files).filter { !$0.isDirectory && $0.path.hasSuffix(".tex") }
        let candidates = tex.filter { file in
            guard let url = try? resolve(file.path, in: root), let text = try? read(url).text else { return false }
            return LaTeXParser.uncomment(text).range(of: #"\\documentclass\s*(?:\[[^\]]*\])?\s*\{"#, options: .regularExpression) != nil
        }
        return candidates.first(where: { $0.path == "main.tex" })?.path ?? candidates.first?.path ?? tex.first?.path
    }
    public static func fingerprint(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func metadataDirectory(for root: URL, base: URL? = nil) -> URL {
        let support = base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TeXium", isDirectory: true)
        return support.appendingPathComponent("Projects/" + fingerprint(Data(root.resolvingSymlinksInPath().path.utf8)), isDirectory: true)
    }
}
