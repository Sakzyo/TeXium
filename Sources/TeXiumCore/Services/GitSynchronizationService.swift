import Foundation

public enum GitSynchronizationService {
    public static func perform(_ action: GitSyncAction, root: URL, remoteName: String? = nil, authentication: GitAuthentication? = nil) async throws -> GitSyncResult {
        var state = try await GitService.inspect(root: root, preferredRemote: remoteName)
        if let remoteName, state.remoteName != remoteName {
            throw TeXiumError.message("The selected remote no longer exists. Refresh and choose a repository before synchronizing.")
        }
        guard let remote = state.remote else { throw TeXiumError.message("Connect this project to a repository before synchronizing.") }
        guard remote.fetchURLs.count == 1, remote.pushURLs.count == 1 else { throw TeXiumError.message("Synchronization requires one fetch URL and one push URL for the selected remote.") }
        let fetchRepository = try? GitHubRepository(remote.fetchURLs[0])
        let pushRepository = try? GitHubRepository(remote.pushURLs[0])
        guard remote.fetchURLs == remote.pushURLs || (fetchRepository != nil && fetchRepository?.fullName.lowercased() == pushRepository?.fullName.lowercased()) else {
            throw TeXiumError.message("This remote fetches from one repository and pushes to another. Use separate named remotes so the synchronization destination is unambiguous.")
        }
        guard !remote.name.hasPrefix("-"), !remote.name.contains(":") else { throw TeXiumError.message("Rename this remote before synchronizing.") }
        if action != .fetch { try validateWritable(state) }
        let originalBranch = state.branch
        let originalTarget = state.remoteBranch
        let originalHead = action == .fetch ? "" : try await GitService.run(["rev-parse", "HEAD"], root: root)
        let previouslyTracked = state.upstream == state.target
        // Credentials are only supplied for a validated HTTPS GitHub destination.
        let auth = fetchRepository?.usesSSH == false ? authentication : nil
        var log = try await GitService.run(["fetch", "--prune", "--", remote.name], root: root, authentication: auth)
        try Task.checkCancellation()
        if action == .fetch {
            state = try await GitService.inspect(root: root, preferredRemote: remote.name)
            return GitSyncResult(state: state, message: "Fetched \(remote.displayName). \(state.summary).", log: log)
        }
        // Check the actual branch advertisement, including a branch omitted by a
        // single-branch clone's fetch refspec. Missing branches are never pulled.
        let branchRef = "refs/heads/" + state.remoteBranch
        let trackingRef = "refs/remotes/\(remote.name)/\(state.remoteBranch)"
        let advertised = try await GitService.run(["ls-remote", "--heads", "--", remote.name, branchRef], root: root, authentication: auth)
        if !advertised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log += try await GitService.run(["fetch", "--", remote.name, "+\(branchRef):\(trackingRef)"], root: root, authentication: auth)
        } else {
            // A deleted remote branch must not leave cached counts suggesting a
            // safe pull. Deleting only our tracking ref does not change source.
            _ = try await GitService.run(["update-ref", "-d", trackingRef], root: root)
        }
        state = try await GitService.inspect(root: root, preferredRemote: remote.name)
        try validateWritable(state) // Recheck after the network wait.
        guard state.remote?.fetchURLs == remote.fetchURLs, state.remote?.pushURLs == remote.pushURLs,
              state.branch == originalBranch, state.remoteBranch == originalTarget,
              try await GitService.run(["rev-parse", "HEAD"], root: root) == originalHead else {
            throw TeXiumError.message("The local branch changed while fetching. Review the current branch and synchronize again.")
        }
        if !state.remoteBranchExists && previouslyTracked && action != .push {
            throw TeXiumError.message("The tracked remote branch was deleted. Your local commits are intact. Use Push explicitly if you intend to publish it again.")
        }
        guard !(state.ahead > 0 && state.behind > 0) else {
            throw TeXiumError.message("Local and remote branches have diverged (\(state.ahead) outgoing, \(state.behind) incoming). No source was overwritten and no commits were pushed. Merge or rebase in your Git client, resolve conflicts, then synchronize again.")
        }
        if action == .pull && !state.remoteBranchExists { throw TeXiumError.message("The remote branch \(state.target) does not exist yet. Push or Synchronize to publish the local branch.") }
        if action == .push && state.behind > 0 { throw TeXiumError.message("There are \(state.behind) incoming commits. Pull or Synchronize before pushing.") }
        var pulled = 0
        if action != .push && state.behind > 0 {
            pulled = state.behind
            log += try await GitService.run(["merge", "--ff-only", trackingRef], root: root)
        }
        try Task.checkCancellation()
        let shouldPush = action == .push || (action == .synchronize && (state.ahead > 0 || !state.remoteBranchExists))
        let checked = try await GitService.inspect(root: root, preferredRemote: remote.name)
        try validateWritable(checked)
        guard checked.remote?.fetchURLs == remote.fetchURLs, checked.remote?.pushURLs == remote.pushURLs,
              checked.branch == originalBranch, checked.remoteBranch == originalTarget else {
            throw TeXiumError.message("The branch changed during synchronization. Review it before continuing.")
        }
        if shouldPush {
            // A normal push preserves server-side non-fast-forward and branch
            // protection checks even if another writer pushes after our fetch.
            let pushAuth = pushRepository?.usesSSH == false ? authentication : nil
            log += try await GitService.run(["push", "--set-upstream", "--", remote.name, "HEAD:" + branchRef], root: root, authentication: pushAuth)
        } else {
            _ = try await GitService.run(["branch", "--set-upstream-to=" + state.target, state.branch], root: root)
        }
        let result = try await GitService.inspect(root: root, preferredRemote: remote.name)
        let message = action == .pull ? "Pulled \(pulled) commit\(pulled == 1 ? "" : "s") from \(result.target)." : action == .push ? "Pushed to \(result.target)." : "Synchronized with \(remote.displayName) · \(result.remoteBranch)."
        return GitSyncResult(state: result, message: message, log: log)
    }
    private static func validateWritable(_ state: GitRepositoryState) throws {
        guard !state.operationInProgress && !state.conflicted else { throw TeXiumError.message("Finish the current merge, rebase, or conflict resolution before synchronizing. Your files have been preserved.") }
        guard !state.branch.isEmpty else { throw TeXiumError.message("This project has a detached HEAD. Switch to a local branch before synchronizing.") }
        guard state.hasCommits else { throw TeXiumError.message("Create the first local commit before synchronizing this project.") }
        guard state.files.isEmpty else { throw TeXiumError.message("Commit your changes before synchronizing. TeXium does not automatically stash or overwrite uncommitted work.") }
    }
}
