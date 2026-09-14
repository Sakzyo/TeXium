import Foundation

public struct GitHubRepository: Equatable, Sendable {
    public let owner: String
    public let name: String
    public let usesSSH: Bool
    public var fullName: String { owner + "/" + name }
    public var webURL: URL { URL(string: "https://github.com/" + fullName)! }
    public var cloneURL: String { usesSSH ? "git@github.com:\(fullName).git" : "https://github.com/\(fullName).git" }

    public init(_ remote: String) throws {
        let value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        var path: String
        if value.hasPrefix("git@github.com:") {
            usesSSH = true; path = String(value.dropFirst("git@github.com:".count))
        } else {
            guard let url = URLComponents(string: value), url.host?.lowercased() == "github.com", url.port == nil,
                  url.query == nil, url.fragment == nil, url.password == nil,
                  (url.scheme == "https" && url.user == nil) || (url.scheme == "ssh" && url.user == "git") else {
                throw TeXiumError.message("Enter a GitHub repository URL, such as https://github.com/owner/project or git@github.com:owner/project.git. Keep access tokens in Settings, not in the URL.")
            }
            usesSSH = url.scheme == "ssh"; path = String(url.path.dropFirst())
        }
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, Self.validAccount(parts[0]),
              parts[1].range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
              ![".", ".."].contains(parts[1]) else { throw TeXiumError.message("The GitHub URL must identify an owner and a repository, without a branch or file path.") }
        owner = parts[0]; name = parts[1]
    }
    public static func validAccount(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$"#, options: .regularExpression) != nil
    }
}

public struct GitRemote: Identifiable, Equatable, Sendable {
    public let name: String
    public let fetchURLs: [String]
    public let pushURLs: [String]
    public var id: String { name }
    public var github: GitHubRepository? { fetchURLs.first.flatMap { try? GitHubRepository($0) } }
    public var displayName: String { github?.fullName ?? name }
}

public struct GitRepositoryState: Sendable {
    public let branch: String
    public let hasCommits: Bool
    public let files: [GitFile]
    public let remotes: [GitRemote]
    public let remoteName: String?
    public let remoteBranch: String
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let remoteBranchExists: Bool
    public let operationInProgress: Bool
    public var remote: GitRemote? { remotes.first { $0.name == remoteName } }
    public var conflicted: Bool { files.contains(where: \.isConflict) }
    public var staged: [GitFile] { files.filter(\.isStaged) }
    public var target: String { remoteName.map { $0 + "/" + remoteBranch } ?? "No remote" }
    public var summary: String {
        if operationInProgress || conflicted { return "Resolve the Git operation in progress" }
        if branch.isEmpty { return "Detached HEAD · switch to a branch" }
        if !hasCommits { return "Create your first commit" }
        if remote == nil { return "Connect a remote repository" }
        if !remoteBranchExists { return "Ready to publish \(remoteBranch)" }
        if ahead > 0 && behind > 0 { return "Branches have diverged" }
        if behind > 0 { return "\(behind) incoming commit\(behind == 1 ? "" : "s")" }
        if ahead > 0 { return "\(ahead) outgoing commit\(ahead == 1 ? "" : "s")" }
        return "Up to date with \(target)"
    }
}

public enum GitSyncAction: String, Sendable { case fetch, pull, push, synchronize }
public struct GitSyncResult: Sendable {
    public let state: GitRepositoryState
    public let message: String
    public let log: String
}

/// A helper executable and public account name, never an access token.
public struct GitAuthentication: Sendable {
    public let executable: URL
    public let account: String
    public init(executable: URL, account: String) { self.executable = executable; self.account = account }
    public var configuration: [String] {
        let quoted = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return ["-c", "credential.helper=", "-c", "credential.helper=!\(quoted) --git-credential",
                "-c", "credential.username=\(account)", "-c", "http.followRedirects=false"]
    }
}
