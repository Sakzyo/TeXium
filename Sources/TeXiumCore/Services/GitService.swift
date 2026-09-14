import Foundation

public struct GitFile: Identifiable, Sendable {
    public var id: String { path }
    public let status: String
    public let path: String
    public var isConflict: Bool { ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(status) }
    public var isStaged: Bool { status.first.map { $0 != " " && $0 != "?" && $0 != "!" } ?? false }
}
public enum GitService {
    public static func execute(_ args: [String], root: URL, authentication: GitAuthentication? = nil) async throws -> ProcessResult {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_PAGER"] = "cat"
        env["LC_ALL"] = "C"
        if env["GIT_SSH_COMMAND"] == nil { env["GIT_SSH_COMMAND"] = "ssh -oBatchMode=yes -oConnectTimeout=15" }
        // A GUI Git operation must not wait on a hidden terminal or an askpass UI.
        env["GIT_ASKPASS"] = "/usr/bin/false"; env["SSH_ASKPASS"] = "/usr/bin/false"
        return try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: ["-c", "core.quotepath=false", "-c", "http.lowSpeedLimit=1", "-c", "http.lowSpeedTime=30"] + (authentication?.configuration ?? []) + args, directory: root, environment: env)
    }
    public static func run(_ args: [String], root: URL, authentication: GitAuthentication? = nil) async throws -> String {
        let result = try await execute(args, root: root, authentication: authentication)
        guard result.status == 0 else { throw TeXiumError.message(result.output.isEmpty ? "Git exited with status \(result.status)." : result.output) }
        return result.output
    }
    public static func validateRoot(_ root: URL) async throws {
        let top = try await run(["rev-parse", "--show-toplevel"], root: root).trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(fileURLWithPath: top).resolvingSymlinksInPath() == root.resolvingSymlinksInPath() else {
            throw TeXiumError.message("This folder belongs to a Git repository at \(top). Open that repository’s root as your project to use Git actions safely.")
        }
    }
    public static func status(root: URL) async throws -> [GitFile] {
        try await validateRoot(root)
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
        _ = try await run(["init", "--initial-branch=main"], root: root)
        let ignore = root.appendingPathComponent(".gitignore")
        let old = (try? String(contentsOf: ignore, encoding: .utf8)) ?? ""
        if !old.contains(".texium-build/") { try (old + "\n.texium-build/\n.DS_Store\n").write(to: ignore, atomically: true, encoding: .utf8) }
    }
    public static func checkout(_ branch: String, root: URL) async throws {
        guard try await status(root: root).isEmpty else { throw TeXiumError.message("Commit or stash your changes before switching branches. TeXium will not overwrite uncommitted work.") }
        guard !branch.hasPrefix("-"), !branch.isEmpty else { throw TeXiumError.message("Enter an existing branch name.") }
        _ = try await run(["switch", branch], root: root)
    }

    public static func inspect(root: URL, preferredRemote: String? = nil) async throws -> GitRepositoryState {
        let files = try await status(root: root)
        let branchResult = try await execute(["symbolic-ref", "--quiet", "--short", "HEAD"], root: root)
        let branch = branchResult.status == 0 ? branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let hasCommits = try await execute(["rev-parse", "--verify", "HEAD"], root: root).status == 0
        let remoteNames = try await run(["remote"], root: root).split(separator: "\n").map(String.init)
        var remotes: [GitRemote] = []
        for name in remoteNames {
            let fetch = try await run(["remote", "get-url", "--all", name], root: root).split(separator: "\n").map(String.init)
            let push = try await run(["remote", "get-url", "--push", "--all", name], root: root).split(separator: "\n").map(String.init)
            remotes.append(GitRemote(name: name, fetchURLs: fetch, pushURLs: push))
        }
        let tracking = branch.isEmpty ? "" : try await run(["for-each-ref", "--format=%(upstream:remotename)%09%(upstream:remoteref)%09%(upstream:short)", "refs/heads/" + branch], root: root)
        let parts = tracking.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        let upstreamRemote = parts.first.flatMap { $0.isEmpty || $0 == "." ? nil : $0 }
        let chosen = [preferredRemote, upstreamRemote, "origin", remotes.first?.name].compactMap { $0 }.first { name in remotes.contains { $0.name == name } }
        let remoteBranch = chosen == upstreamRemote && parts.count > 1 && parts[1].hasPrefix("refs/heads/") ? String(parts[1].dropFirst(11)) : branch
        let upstream = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        let ref = "refs/remotes/\(chosen ?? "origin")/\(remoteBranch)"
        let exists = chosen != nil && !remoteBranch.isEmpty ? try await execute(["show-ref", "--verify", "--quiet", ref], root: root).status == 0 : false
        var ahead = 0; var behind = 0
        if hasCommits && exists {
            let counts = try await run(["rev-list", "--left-right", "--count", "HEAD..." + ref], root: root).split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
            if counts.count == 2 { ahead = counts[0]; behind = counts[1] }
        } else if hasCommits { ahead = Int(try await run(["rev-list", "--count", "HEAD"], root: root).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        var inProgress = false
        for marker in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer"] {
            let path = try await run(["rev-parse", "--git-path", marker], root: root).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = (path as NSString).isAbsolutePath ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { inProgress = true }
        }
        return GitRepositoryState(branch: branch, hasCommits: hasCommits, files: files, remotes: remotes, remoteName: chosen, remoteBranch: remoteBranch, upstream: upstream, ahead: ahead, behind: behind, remoteBranchExists: exists, operationInProgress: inProgress)
    }

    public static func connectGitHub(_ repository: GitHubRepository, remoteName: String, root: URL) async throws {
        try await validateRoot(root)
        guard remoteName.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else { throw TeXiumError.message("Use a remote name such as origin or github, containing letters, digits, dashes, or underscores.") }
        let state = try await inspect(root: root)
        if let remote = state.remotes.first(where: { $0.name == remoteName }) {
            guard remote.fetchURLs.count == 1, remote.pushURLs.count == 1,
                  (try? GitHubRepository(remote.fetchURLs[0])) == repository,
                  (try? GitHubRepository(remote.pushURLs[0])) == repository else {
                throw TeXiumError.message("The remote ‘\(remoteName)’ already points elsewhere. Choose a new remote name; TeXium will preserve the existing connection.")
            }
            return
        }
        _ = try await run(["remote", "add", remoteName, repository.cloneURL], root: root)
    }

    public static func clone(_ remote: String, to destination: URL, authentication: GitAuthentication? = nil) async throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw TeXiumError.message("Choose a new folder for the clone so existing files stay intact.") }
        guard !remote.isEmpty, !remote.hasPrefix("-"), !remote.contains("\n"), !remote.contains("\0") else { throw TeXiumError.message("Enter a valid repository URL.") }
        if let url = URLComponents(string: remote), ["http", "https"].contains(url.scheme ?? ""), url.user != nil || url.password != nil {
            throw TeXiumError.message("Remove credentials from the clone URL. Use Settings → GitHub or your Git credential helper instead.")
        }
        let github = try? GitHubRepository(remote)
        _ = try await run(["clone", "--", remote, destination.path], root: destination.deletingLastPathComponent(), authentication: github?.usesSSH == false ? authentication : nil)
    }

    public static func commit(message: String, stageAll: Bool, root: URL, authorName: String? = nil, authorEmail: String? = nil) async throws {
        let state = try await inspect(root: root)
        guard !state.conflicted && !state.operationInProgress else { throw TeXiumError.message("Finish the current merge or rebase before creating a commit in TeXium.") }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TeXiumError.message("Write a commit message describing your changes.") }
        if let authorName, let authorEmail {
            guard !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, authorEmail.contains("@"),
                  !authorName.contains(where: { $0.isNewline }), !authorEmail.contains(where: { $0.isWhitespace }),
                  !authorName.contains("\0"), !authorEmail.contains("\0") else { throw TeXiumError.message("Enter a commit author name and email address.") }
            _ = try await run(["config", "--local", "user.name", authorName], root: root)
            _ = try await run(["config", "--local", "user.email", authorEmail], root: root)
        }
        if stageAll { _ = try await run(["add", "--all", "--", "."], root: root) }
        guard try await status(root: root).contains(where: \.isStaged) else { throw TeXiumError.message("There are no staged changes to commit.") }
        _ = try await run(["commit", "-m", message], root: root)
    }
}
