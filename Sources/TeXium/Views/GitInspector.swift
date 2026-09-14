import SwiftUI
import TeXiumCore

struct GitInspector: View {
    @Bindable var session: ProjectSession
    @State private var branch = ""
    @State private var detail = ""
    @State private var showDetail = false
    @Environment(\.openSettings) private var openSettings
    private var busy: Bool { session.operationBusy || session.building || session.gitTask != nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("GitHub Synchronization", systemImage: "arrow.triangle.branch").font(.headline)
                        Spacer()
                        Button("Refresh Local Status", systemImage: "arrow.clockwise") { Task { await session.refreshGit() } }.labelStyle(.iconOnly).disabled(busy)
                    }
                    if let state = session.gitState {
                        repository(state)
                    } else {
                        Text("Connect this folder to an existing GitHub repository. Your project remains available offline.").foregroundStyle(.secondary)
                        Button("Connect GitHub Repository…") { session.sheet = .gitConnect }.disabled(busy)
                        Button("Initialize Local Git") {
                            session.gitOperation("Initializing Git…") { try await GitService.initialize(root: session.root); session.gitMessage = "Initialized local Git. Review and commit your files next." }
                        }.disabled(busy)
                    }
                    if !session.gitMessage.isEmpty {
                        Label(session.gitMessage, systemImage: session.gitFailed ? "exclamationmark.triangle" : "info.circle")
                            .foregroundStyle(session.gitFailed ? Color.orange : Color.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if session.gitTask != nil {
                        HStack { ProgressView().controlSize(.small); Text("Git is working…"); Spacer(); Button("Stop") { session.gitTask?.cancel() } }
                    }
                    if !session.gitLog.isEmpty {
                        Button("Show Operation Log…") { detail = session.gitLog; showDetail = true }
                    }
                }.font(.callout).padding(12)
            }.frame(maxHeight: session.isGitRepository ? 340 : .infinity)
            if let state = session.gitState {
                Divider()
                HStack { Text("Changes · \(state.files.count)"); Spacer(); Text("\(state.staged.count) staged").foregroundStyle(.secondary) }.font(.caption).padding(12)
                if state.files.isEmpty {
                    ContentUnavailableView("Working Tree Clean", systemImage: "checkmark.circle", description: Text("Saved changes will appear here."))
                } else {
                    List(state.files) { file in
                        HStack(alignment: .top) {
                            Text(file.status).font(.system(.caption, design: .monospaced)).foregroundStyle(file.isConflict ? Color.orange : Color.secondary)
                            Text(file.path).lineLimit(2).help(file.path)
                            Spacer(minLength: 0)
                            if file.isStaged { Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary).help("Staged") }
                        }
                        .contextMenu {
                            Button("Show Diff") { showDiff(file) }
                            Button("Stage") { session.stageGit(file.path) }.disabled(busy)
                            Button("Unstage") { session.stageGit(file.path, unstage: true) }.disabled(busy || !file.isStaged)
                            Button("Open") { Task { await session.select(file.path) } }
                        }
                    }.listStyle(.inset)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Stage All") { session.stageGit() }.disabled(state.files.isEmpty)
                        Spacer()
                        Button("Review Commit…") { session.sheet = .gitCommit }.disabled(state.files.isEmpty || state.conflicted || state.operationInProgress)
                    }
                    HStack { TextField("Existing local branch", text: $branch); Button("Switch") { session.switchGitBranch(branch) }.disabled(branch.isEmpty) }
                    Text("Sync uses committed files. Pulls only fast-forward; conflicts and diverged history require resolution in your Git client.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).disabled(busy)
            }
        }
        .task { await session.refreshGit() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in if !busy { Task { await session.refreshGit() } } }
        .sheet(isPresented: $showDetail) {
            VStack(alignment: .leading) { Text("Git Details").font(.title2).padding(); NativeTextDisplay(text: detail, diff: true); HStack { Spacer(); Button("Done") { showDetail = false }.keyboardShortcut(.defaultAction) }.padding() }.frame(width: 850, height: 580)
        }
    }

    @ViewBuilder private func repository(_ state: GitRepositoryState) -> some View {
        if let remote = state.remote {
            if let repository = remote.github { Link(repository.fullName, destination: repository.webURL).font(.title3.weight(.semibold)) }
            else { Text(remote.displayName).font(.title3.weight(.semibold)) }
            if state.remotes.count > 1 {
                Picker("Remote", selection: Binding(get: { state.remoteName ?? "" }, set: { value in session.preferredGitRemote = value; session.persistPreferences(); Task { await session.refreshGit() } })) {
                    ForEach(state.remotes) { Text($0.name + " · " + $0.displayName).tag($0.name) }
                }.disabled(busy)
            }
            Label(state.branch.isEmpty ? "Detached HEAD" : state.branch + " → " + state.target, systemImage: "arrow.triangle.branch").font(.caption).textSelection(.enabled)
            HStack(spacing: 18) {
                Label("\(state.behind) incoming", systemImage: "arrow.down")
                Label("\(state.ahead) outgoing", systemImage: "arrow.up")
            }.font(.caption.monospacedDigit())
            Text(state.summary).foregroundStyle(state.conflicted || (state.ahead > 0 && state.behind > 0) ? Color.orange : Color.secondary)
            HStack {
                Button("Synchronize", systemImage: "arrow.triangle.2.circlepath") { session.synchronizeGit(.synchronize) }.disabled(busy || !state.hasCommits || state.branch.isEmpty)
                Menu {
                    Button("Fetch Remote Status") { session.synchronizeGit(.fetch) }
                    Button("Pull (Fast-Forward Only)") { session.synchronizeGit(.pull) }
                    Button("Push Local Commits") { session.synchronizeGit(.push) }
                    Divider()
                    Button("Connect Another Repository…") { session.sheet = .gitConnect }
                    Button("GitHub Authentication Settings…") { openSettings() }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).disabled(busy)
            }
            Text(session.gitLastFetched.map { "Fetched " + $0.formatted(date: .omitted, time: .shortened) } ?? "Cached status · Fetch to check the remote").font(.caption).foregroundStyle(.secondary)
        } else {
            Label(state.branch.isEmpty ? "Local repository" : state.branch, systemImage: "arrow.triangle.branch")
            Text(state.summary).foregroundStyle(.secondary)
            Button("Connect GitHub Repository…") { session.sheet = .gitConnect }.disabled(busy)
        }
    }
    private func showDiff(_ file: GitFile) {
        Task {
            do {
                let base = session.gitState?.hasCommits == true ? ["HEAD"] : ["--cached"]
                detail = try await GitService.run(["diff"] + base + ["--", file.path], root: session.root)
                if detail.isEmpty { detail = "No tracked diff. Stage an untracked file to review its contents here." }
                showDetail = true
            } catch { session.present(error) }
        }
    }
}

struct GitHubConnectionSheet: View {
    @Bindable var session: ProjectSession
    @State private var url = ""
    @State private var name = "origin"
    private var repository: GitHubRepository? { try? GitHubRepository(url) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect GitHub Repository", systemImage: "arrow.triangle.branch").font(.title2)
            Text("Create a repository on GitHub first, then paste its HTTPS or SSH URL. For a repository with existing work, cloning from the Project Browser is the easiest starting point.").foregroundStyle(.secondary)
            TextField("https://github.com/owner/project", text: $url)
            TextField("Remote name", text: $name)
            if let repository { Label(repository.fullName, systemImage: "checkmark.circle").foregroundStyle(.green) }
            if !session.isGitRepository { Text("TeXium will initialize local Git in this project folder and exclude its build cache.").font(.callout) }
            Text("Connecting saves the remote URL locally. Fetch checks access; Synchronize uploads committed work. HTTPS credentials can be saved in Settings → GitHub. SSH uses your configured keys.").font(.callout).foregroundStyle(.secondary)
            if session.gitFailed { Text(session.gitMessage).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Link("Create on GitHub", destination: URL(string: "https://github.com/new")!)
                Spacer()
                Button("Cancel") { session.sheet = nil }.keyboardShortcut(.cancelAction)
                Button("Connect") { session.connectGitHub(url: url, name: name) }.keyboardShortcut(.defaultAction).disabled(repository == nil || name.isEmpty)
            }.disabled(session.gitTask != nil)
        }.padding(24).frame(width: 560)
        .onAppear { if session.gitState?.remotes.contains(where: { $0.name == "origin" }) == true { name = "github" } }
        .interactiveDismissDisabled(session.gitTask != nil)
    }
}

struct GitCommitSheet: View {
    @Bindable var session: ProjectSession
    @State private var message = ""
    @State private var stageAll = true
    @State private var authorName = ""
    @State private var authorEmail = ""
    private var files: [GitFile] { stageAll ? session.gitFiles : session.gitFiles.filter(\.isStaged) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Commit").font(.title2)
            Toggle("Include all changed and untracked files", isOn: $stageAll)
            Text(stageAll ? "All files below will be staged and committed. Review untracked files and your .gitignore before including private material." : "Only the contents already staged in Git will be committed.").font(.callout).foregroundStyle(.secondary)
            List(files) { file in HStack { Text(file.status).font(.system(.caption, design: .monospaced)); Text(file.path) } }.frame(height: 190)
            TextField("Commit message", text: $message)
            HStack { TextField("Author name", text: $authorName); TextField("Author email", text: $authorEmail) }
            Text("The author identity is saved for this repository and included in commits. You can use your GitHub noreply email.").font(.caption).foregroundStyle(.secondary)
            if let state = session.gitState, let remote = state.remote {
                Text("Commit & Sync will download incoming commits and upload your committed history to \(remote.displayName), branch \(state.remoteBranch).").font(.callout).foregroundStyle(.secondary)
            }
            if session.gitFailed { Text(session.gitMessage).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Cancel") { session.sheet = nil }.keyboardShortcut(.cancelAction).disabled(session.gitTask != nil)
                Spacer()
                Button("Commit Locally") { session.commitGit(message: message, stageAll: stageAll, synchronize: false, authorName: authorName, authorEmail: authorEmail) }.keyboardShortcut(.defaultAction).disabled(session.gitTask != nil || files.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authorName.isEmpty || !authorEmail.contains("@"))
                Button("Commit & Sync") { session.commitGit(message: message, stageAll: stageAll, synchronize: true, authorName: authorName, authorEmail: authorEmail) }.disabled(session.gitState?.remote == nil || session.gitTask != nil || files.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authorName.isEmpty || !authorEmail.contains("@"))
            }
        }.padding(24).frame(width: 600)
        .task {
            try? await session.saveAll(); await session.refreshGit()
            authorName = (try? await GitService.run(["config", "--get", "user.name"], root: session.root).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            authorEmail = (try? await GitService.run(["config", "--get", "user.email"], root: session.root).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        }
        .interactiveDismissDisabled(session.gitTask != nil)
    }
}
