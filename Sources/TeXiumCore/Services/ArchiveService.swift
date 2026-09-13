import Foundation

public enum ExportPreset: String, CaseIterable, Identifiable, Sendable {
    case source = "LaTeX source", submission = "Submission with bibliography", generated = "Generated files"
    public var id: String { rawValue }
}
public enum ArchiveService {
    public static let auxiliaryExtensions: Set<String> = ["aux", "log", "toc", "out", "blg", "bcf", "fls", "fdb_latexmk", "synctex", "nav", "snm", "vrb", "idx", "ilg", "lof", "lot"]
    public static func include(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard !parts.contains(where: { $0.hasPrefix(".") }), !path.hasSuffix(".synctex.gz"), !path.hasSuffix(".run.xml") else { return false }
        return !auxiliaryExtensions.contains((path as NSString).pathExtension.lowercased())
    }
    /// Inspect the ZIP central directory before asking the system extractor to
    /// touch disk. ZIP64, encrypted files, symlinks, traversal and bombs are refused.
    public static func validateZIP(_ data: Data) throws {
        func fail() -> TeXiumError { .message("This ZIP is unsupported or unsafe. Use a standard, unencrypted ZIP without symbolic links, paths outside the project, or more than 1 GB of expanded data.") }
        func u16(_ n: Int) -> UInt16 { UInt16(data[n]) | UInt16(data[n + 1]) << 8 }
        func u32(_ n: Int) -> UInt32 { UInt32(u16(n)) | UInt32(u16(n + 2)) << 16 }
        guard data.count >= 22 else { throw fail() }
        var end: Int?
        for n in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if u32(n) == 0x06054b50 && n + 22 + Int(u16(n + 20)) == data.count { end = n; break }
        }
        guard let end, u16(end + 4) == 0, u16(end + 6) == 0, u16(end + 8) == u16(end + 10), u16(end + 10) < 50_000 else { throw fail() }
        var cursor = Int(u32(end + 16)); let centralEnd = cursor + Int(u32(end + 12)); var total: UInt64 = 0; var names = Set<String>()
        guard centralEnd <= end else { throw fail() }
        for _ in 0..<Int(u16(end + 10)) {
            guard cursor + 46 <= centralEnd, u32(cursor) == 0x02014b50 else { throw fail() }
            let size = Int(u16(cursor + 28)); let extra = Int(u16(cursor + 30)); let comment = Int(u16(cursor + 32)); let mode = u32(cursor + 38) >> 16
            guard cursor + 46 + size + extra + comment <= centralEnd, u16(cursor + 8) & 1 == 0, mode & 0xf000 != 0xa000, u32(cursor + 24) != UInt32.max else { throw fail() }
            guard let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + size), encoding: .utf8), !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0"), !name.split(separator: "/").contains(".."), !name.split(separator: "/").contains(".git"), names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw fail() }
            let local = Int(u32(cursor + 42))
            guard local + 30 <= data.count, u32(local) == 0x04034b50 else { throw fail() }
            let localSize = Int(u16(local + 26))
            guard local + 30 + localSize <= data.count, data.subdata(in: local + 30..<local + 30 + localSize) == data.subdata(in: cursor + 46..<cursor + 46 + size) else { throw fail() }
            total += UInt64(u32(cursor + 24)); guard total <= 1_073_741_824 else { throw fail() }
            cursor += 46 + size + extra + comment
        }
        guard cursor == centralEnd else { throw fail() }
    }
    public static func importZIP(_ zip: URL, to destination: URL) async throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw TeXiumError.message("Import into a new folder to preserve existing files.") }
        let size = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 512 * 1024 * 1024 else { throw TeXiumError.message("ZIP import is limited to 512 MB compressed.") }
        try validateZIP(Data(contentsOf: zip, options: .mappedIfSafe))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", zip.path, temporary.path], directory: temporary)
        guard result.status == 0 else { throw TeXiumError.message(result.output) }
        let contents = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).filter { $0.lastPathComponent != "__MACOSX" }
        let source = contents.count == 1 && (try? contents[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? contents[0] : temporary
        try FileManager.default.copyItem(at: source, to: destination)
    }
    public static func export(root: URL, to destination: URL, preset: ExportPreset, zip: Bool = true) async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if preset == .generated {
            let build = try CompilationService.buildDirectory(root: root)
            for file in try FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil) where file.lastPathComponent != "preview" { try FileManager.default.copyItem(at: file, to: temporary.appendingPathComponent(file.lastPathComponent)) }
        } else {
            for file in ProjectFileSystem.flatten(try ProjectFileSystem.tree(at: root)) where !file.isDirectory && include(file.path) {
                let source = try ProjectFileSystem.resolve(file.path, in: root)
                let target = try ProjectFileSystem.resolve(file.path, in: temporary)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Materialize file bytes rather than copying a link outside the archive.
                try Data(contentsOf: source).write(to: target, options: .atomic)
            }
            if preset == .submission {
                let build = try CompilationService.buildDirectory(root: root)
                for file in (try? FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "bbl" { try Data(contentsOf: file).write(to: temporary.appendingPathComponent(file.lastPathComponent), options: .atomic) }
            }
        }
        if zip {
            let stagedZIP = temporary.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".zip")
            defer { try? FileManager.default.removeItem(at: stagedZIP) }
            let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-c", "-k", "--norsrc", "--noextattr", temporary.path, stagedZIP.path], directory: temporary)
            guard result.status == 0 else { throw TeXiumError.message(result.output) }
            try Data(contentsOf: stagedZIP).write(to: destination, options: .atomic)
        } else {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw TeXiumError.message("Choose a new folder for the source export.") }
            try FileManager.default.copyItem(at: temporary, to: destination)
        }
    }
}
