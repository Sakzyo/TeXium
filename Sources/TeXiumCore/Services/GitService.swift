import Foundation

public struct GitFile: Identifiable, Sendable {
    public var id: String { path }
    public let status: String
    public let path: String
}
public enum GitService {
    public static func run(_ args: [String], root: URL) async throws -> String {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_PAGER"] = "cat"
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: ["-c", "core.quotepath=false"] + args, directory: root, environment: env)
        guard result.status == 0 else { throw TeXiumError.message(result.output.isEmpty ? "Git exited with status \(result.status)." : result.output) }
        return result.output
    }
    public static func status(root: URL) async throws -> [GitFile] {
        let top = try await run(["rev-parse", "--show-toplevel"], root: root).trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(fileURLWithPath: top).resolvingSymlinksInPath() == root.resolvingSymlinksInPath() else {
            throw TeXiumError.message("This folder belongs to a Git repository at \(top). Open that repository’s root as your project to use Git actions safely.")
        }
        let output = try await run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], root: root)
        let records = output.split(separator: "\0", omittingEmptySubsequences: true)
        var files: [GitFile] = []; var i = 0
        while i < records.count {
            let record = String(records[i]); i += 1
            guard record.count >= 4 else { continue }
            let status = String(record.prefix(2)); let path = String(record.dropFirst(3))
            files.append(GitFile(status: status, path: path))
            if status.contains("R") || status.contains("C") { i += 1 }
        }
        return files
    }
    public static func initialize(root: URL) async throws {
        if let top = try? await run(["rev-parse", "--show-toplevel"], root: root).trimmingCharacters(in: .whitespacesAndNewlines), URL(fileURLWithPath: top).resolvingSymlinksInPath() != root.resolvingSymlinksInPath() {
            throw TeXiumError.message("A parent Git repository already exists at \(top). Open its root instead of creating a nested repository.")
        }
        _ = try await run(["init"], root: root)
        let ignore = root.appendingPathComponent(".gitignore")
        let old = (try? String(contentsOf: ignore, encoding: .utf8)) ?? ""
        if !old.contains(".texium-build/") { try (old + "\n.texium-build/\n.DS_Store\n").write(to: ignore, atomically: true, encoding: .utf8) }
    }
    public static func checkout(_ branch: String, root: URL) async throws {
        guard try await status(root: root).isEmpty else { throw TeXiumError.message("Commit or stash your changes before switching branches. TeXium will not overwrite uncommitted work.") }
        guard !branch.hasPrefix("-"), !branch.isEmpty else { throw TeXiumError.message("Enter an existing branch name.") }
        _ = try await run(["switch", branch], root: root)
    }
}
