import Foundation

public struct Revision: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public var label: String
    public let files: [String: String]
}
public actor HistoryService {
    public let root: URL
    public let storage: URL
    public init(root: URL, storage: URL? = nil) {
        self.root = root; self.storage = storage ?? ProjectFileSystem.metadataDirectory(for: root).appendingPathComponent("History")
    }
    public func revisions() throws -> [Revision] {
        let url = storage.appendingPathComponent("revisions.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Revision].self, from: Data(contentsOf: url))
    }
    @discardableResult public func snapshot(label: String) throws -> Revision {
        let objects = storage.appendingPathComponent("Objects")
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        var files: [String: String] = [:]
        for item in ProjectFileSystem.flatten(try ProjectFileSystem.tree(at: root)) where !item.isDirectory {
            let url = try ProjectFileSystem.resolve(item.path, in: root)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            guard (values.fileSize ?? 0) <= 256 * 1024 * 1024 else { throw TeXiumError.message("History cannot snapshot files larger than 256 MB: \(item.path)") }
            let data = try Data(contentsOf: url); let hash = ProjectFileSystem.fingerprint(data)
            let object = objects.appendingPathComponent(hash)
            if !FileManager.default.fileExists(atPath: object.path) { try data.write(to: object, options: .atomic) }
            files[item.path] = hash
        }
        var history = try revisions()
        if let latest = history.first, latest.files == files, label.hasPrefix("Automatic") { return latest }
        let revision = Revision(id: UUID(), date: Date(), label: label, files: files)
        history.insert(revision, at: 0)
        try JSONEncoder().encode(history).write(to: storage.appendingPathComponent("revisions.json"), options: .atomic)
        return revision
    }
    public func data(for revision: Revision, file: String) throws -> Data {
        guard let hash = revision.files[file], hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw TeXiumError.message("This file is not present in the selected revision.") }
        let data = try Data(contentsOf: storage.appendingPathComponent("Objects/" + hash))
        guard ProjectFileSystem.fingerprint(data) == hash else { throw TeXiumError.message("A history object failed its integrity check. The current source has not been changed.") }
        return data
    }
    public func restore(_ revision: Revision, file: String? = nil) throws {
        let selected = file.map { [$0] } ?? Array(revision.files.keys)
        // Validate and load all objects before making any source modifications.
        let changes = try selected.map { path in (try ProjectFileSystem.resolve(path, in: root), try data(for: revision, file: path)) }
        let before = try snapshot(label: "Before restoring \(revision.label)")
        do {
            for (url, data) in changes {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            if file == nil {
                for path in before.files.keys where revision.files[path] == nil {
                    let url = try ProjectFileSystem.resolve(path, in: root)
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
            }
            try snapshot(label: "Restored \(revision.label)")
        } catch {
            throw TeXiumError.message("Restore stopped: \(error.localizedDescription). The complete pre-restore snapshot ‘\(before.label)’ is available in History.")
        }
    }
    public func export(_ revision: Revision, to folder: URL) throws {
        for path in revision.files.keys {
            let url = try ProjectFileSystem.resolve(path, in: folder)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data(for: revision, file: path).write(to: url, options: .atomic)
        }
    }
    public func diff(_ revision: Revision, file: String) async throws -> String {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data(for: revision, file: file).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let current = try ProjectFileSystem.resolve(file, in: root)
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/diff"), arguments: ["-u", "--label", revision.label + "/" + file, "--label", "Current/" + file, temporary.path, current.path], directory: root)
        guard result.status <= 1 else { throw TeXiumError.message(result.output) }
        return result.output.isEmpty ? "No changes in \(file)." : result.output
    }
}
