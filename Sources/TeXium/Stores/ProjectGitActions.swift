import AppKit
import TeXiumCore

extension ProjectSession {
    func showGit() { inspectorTab = "Git"; showInspector = true }

    func refreshGit() async {
        let generation = UUID(); gitRefreshID = generation
        do {
            let state = try await GitService.inspect(root: root, preferredRemote: preferredGitRemote)
            guard gitRefreshID == generation else { return }
            gitState = state; gitFiles = state.files; gitBranch = state.branch; isGitRepository = true
        } catch {
            guard gitRefreshID == generation else { return }
            gitState = nil; gitFiles = []; gitBranch = ""; isGitRepository = false
        }
    }

    /// All project Git mutations share the editor/build exclusion and cancellation lifecycle.
    func gitOperation(_ title: String, body: @escaping @MainActor () async throws -> Void) {
        guard !operationBusy, !building, gitTask == nil else { return }
        guard conflictPath == nil else { error = "Resolve the external file change before using Git."; return }
        operationBusy = true; gitMessage = title; gitLog = ""; gitFailed = false; showGit()
        automaticBuildTask?.cancel(); autosaveTask?.cancel()
        gitTask = Task {
            do { try await saveAll(); try Task.checkCancellation(); try await body() }
            catch is CancellationError {
                gitFailed = true; gitMessage = "Git stopped. Fetch again to check the remote; a push may already have reached the server."
            } catch {
                gitFailed = true; gitMessage = error.localizedDescription; gitLog += "\n" + error.localizedDescription
            }
            operationBusy = false
            // A successful pull can delete clean open files. Close those buffers
            // before reloading, so they cannot be accidentally saved back to disk.
            for path in Array(buffers.keys) where buffers[path]?.dirty == false && !FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
                buffers.removeValue(forKey: path); tabs.removeAll { $0 == path }
                if selected == path { selected = tabs.last }
            }
            // Refresh outside the cancelled operation task as ProcessRunner
            // correctly refuses to launch subprocesses in a cancelled task.
            await Task { await self.externalChanges(); await self.refreshHistory() }.value
            gitTask = nil
        }
    }

    func synchronizeGit(_ action: GitSyncAction) {
        let remote = gitState?.remoteName
        gitOperation(action == .synchronize ? "Synchronizing…" : "Running Git \(action.rawValue)…") {
            if action == .pull || action == .synchronize { _ = try await self.history.snapshot(label: "Before Git \(action.rawValue)") }
            let result = try await GitSynchronizationService.perform(action, root: self.root, remoteName: remote, authentication: GitHubAuthentication.configured)
            self.gitMessage = result.message; self.gitLog = result.log; self.gitLastFetched = Date()
        }
    }

    func connectGitHub(url: String, name: String) {
        gitOperation("Connecting repository…") {
            let repository = try GitHubRepository(url)
            if !self.isGitRepository { try await GitService.initialize(root: self.root) }
            try await GitService.connectGitHub(repository, remoteName: name, root: self.root)
            self.preferredGitRemote = name; self.persistPreferences(); self.sheet = nil
            self.gitMessage = "Connected \(repository.fullName). Fetch to check access and incoming commits."
        }
    }

    func commitGit(message: String, stageAll: Bool, synchronize: Bool, authorName: String, authorEmail: String) {
        let remote = gitState?.remoteName
        gitOperation("Committing changes…") {
            _ = try await self.history.snapshot(label: "Before Git commit")
            try await GitService.commit(message: message, stageAll: stageAll, root: self.root, authorName: authorName, authorEmail: authorEmail)
            self.sheet = nil; self.gitMessage = "Committed locally."
            if synchronize {
                do {
                    let result = try await GitSynchronizationService.perform(.synchronize, root: self.root, remoteName: remote, authentication: GitHubAuthentication.configured)
                    self.gitMessage = result.message; self.gitLog = result.log; self.gitLastFetched = Date()
                } catch { throw TeXiumError.message("Your commit was saved locally. Synchronization did not finish: " + error.localizedDescription) }
            }
        }
    }

    func stageGit(_ path: String? = nil, unstage: Bool = false) {
        gitOperation(unstage ? "Unstaging…" : "Staging…") {
            try await GitService.validateRoot(self.root)
            let state = try await GitService.inspect(root: self.root)
            let arguments = unstage ? (state.hasCommits ? ["reset", "HEAD", "--", path ?? "."] : ["rm", "--cached", "--", path ?? "."]) : ["add", "--all", "--", path ?? "."]
            self.gitLog = try await GitService.run(arguments, root: self.root)
            self.gitMessage = unstage ? "Unstaged selected changes." : "Staged changes for review."
        }
    }

    func switchGitBranch(_ branch: String) {
        gitOperation("Switching branch…") {
            _ = try await self.history.snapshot(label: "Before switching Git branch")
            try await GitService.checkout(branch, root: self.root)
            self.gitMessage = "Switched to \(branch)."
        }
    }
}
