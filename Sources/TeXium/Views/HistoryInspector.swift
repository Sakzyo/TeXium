import SwiftUI
import TeXiumCore

struct HistoryInspector: View {
    @Bindable var session: ProjectSession
    @State private var selected: UUID?
    @State private var chosenFile = ""
    @State private var showDiff = false
    @State private var restore = false
    @State private var restoreWhole = false
    private var revision: Revision? { session.revisions.first { $0.id == selected } }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Local Snapshots").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Take Snapshot", systemImage: "plus") { session.sheet = .snapshot }.labelStyle(.iconOnly) }.padding(12)
            List(session.revisions, selection: $selected) { revision in
                VStack(alignment: .leading, spacing: 5) {
                    Label(revision.label, systemImage: "clock.arrow.circlepath").font(.callout)
                    Text(revision.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text("\(revision.files.count) files").font(.caption).foregroundStyle(.tertiary)
                }.tag(revision.id).padding(.vertical, 3)
            }.listStyle(.inset)
            if let revision {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Picker("File", selection: $chosenFile) { ForEach(revision.files.keys.sorted(), id: \.self) { Text($0).tag($0) } }
                    HStack {
                        Button("Compare") { compare(revision) }.disabled(chosenFile.isEmpty)
                        Menu("Restore") {
                            Button("Restore Selected File…") { restoreWhole = false; restore = true }.disabled(chosenFile.isEmpty)
                            Button("Restore Entire Project…") { restoreWhole = true; restore = true }
                        }
                    }
                    Button("Export This Revision…") { export(revision) }.font(.caption)
                }.padding(12)
            }
        }
        .onChange(of: selected) { _, _ in chosenFile = revision?.files.keys.contains(session.selected ?? "") == true ? session.selected! : (revision?.files.keys.sorted().first ?? "") }
        .sheet(isPresented: $showDiff) {
            VStack(alignment: .leading) {
                Text("Revision Comparison").font(.title2).padding([.top, .horizontal], 20)
                NativeTextDisplay(text: session.historyDiff, diff: true)
                HStack { Spacer(); Button("Done") { showDiff = false }.keyboardShortcut(.defaultAction) }.padding(16)
            }.frame(width: 900, height: 620)
        }
        .alert("Restore \(restoreWhole ? "Entire Project" : chosenFile)?", isPresented: $restore) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) { if let revision { performRestore(revision) } }
        } message: { Text("Your current files will be saved in a new snapshot first. Newer history remains available.\(restoreWhole ? " Files added after this revision will be removed from the project." : "")") }
    }
    private func compare(_ revision: Revision) {
        let file = chosenFile
        Task { do { try await session.saveAll(); session.historyDiff = try await session.history.diff(revision, file: file); showDiff = true } catch { session.present(error) } }
    }
    private func performRestore(_ revision: Revision) {
        guard !session.operationBusy else { return }; session.operationBusy = true
        let file = restoreWhole ? nil : chosenFile
        Task {
            defer { session.operationBusy = false }
            do {
                try await session.saveAll(); try await session.history.restore(revision, file: file)
                session.buffers = [:]; session.tabs = []; await session.refreshIndex(); await session.select(file ?? session.configuration.mainFile)
                session.sourceGeneration += 1; session.stalePDF = session.pdfURL != nil; await session.refreshHistory()
            } catch { session.present(error) }
        }
    }
    private func export(_ revision: Revision) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(session.title) Revision"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { do { guard !FileManager.default.fileExists(atPath: folder.path) else { throw TeXiumError.message("Choose a new folder for the revision export.") }; try await session.history.export(revision, to: folder) } catch { session.present(error) } }
    }
}

struct GitInspector: View {
    @Bindable var session: ProjectSession
    @State private var message = ""
    @State private var branch = ""
    @State private var busy = false
    @State private var diff = ""
    @State private var showingDiff = false
    var body: some View {
        VStack(spacing: 0) {
            if session.isGitRepository {
                HStack { Label(session.gitBranch.isEmpty ? "No commits yet" : session.gitBranch, systemImage: "arrow.triangle.branch"); Spacer(); Button("Refresh", systemImage: "arrow.clockwise") { Task { await session.refreshGit() } }.labelStyle(.iconOnly) }.font(.callout).padding(12)
                List(session.gitFiles) { file in
                    HStack { Text(file.status).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary); Text(file.path).lineLimit(2) }
                        .contextMenu {
                            Button("Show Diff") { showDiff(file) }
                            Button("Stage") { run(["add", "--", file.path]) }
                            Button("Unstage") { run(["reset", "--", file.path]) }
                            Button("Open") { Task { await session.select(file.path) } }
                        }
                }.listStyle(.inset)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Commit message", text: $message)
                    HStack { Button("Stage All") { run(["add", "--all"]) }; Spacer(); Button("Commit Staged") { run(["commit", "-m", message]); message = "" }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    Divider()
                    HStack { TextField("Existing branch", text: $branch); Button("Switch") { switchBranch() }.disabled(branch.isEmpty) }
                    HStack {
                        Button("Fetch") { run(["fetch"]) }
                        Button("Pull") { run(["pull", "--ff-only"]) }
                        Button("Push") { run(["push"]) }
                    }
                }.padding(12).font(.caption).disabled(busy)
            } else {
                ContentUnavailableView { Label("Local Git", systemImage: "arrow.triangle.branch") } description: { Text("Track this project with your installed Git. Local history is also available without Git.") } actions: { Button("Initialize Repository") { Task { do { try await GitService.initialize(root: session.root); await session.refreshGit() } catch { session.present(error) } } } }
            }
            if busy { ProgressView().controlSize(.small).padding(8) }
        }
        .sheet(isPresented: $showingDiff) { VStack { NativeTextDisplay(text: diff, diff: true); Button("Done") { showingDiff = false }.padding(12) }.frame(width: 850, height: 580) }
    }
    private func run(_ arguments: [String]) {
        guard !session.operationBusy else { return }; session.operationBusy = true; busy = true
        Task { defer { busy = false; session.operationBusy = false }; do { try await session.saveAll(); _ = try await session.history.snapshot(label: "Before Git \(arguments.first ?? "operation")"); let output = try await GitService.run(arguments, root: session.root); if !output.isEmpty { session.notice = output }; await session.refreshGit(); session.operationBusy = false; await session.externalChanges() } catch { session.present(error) } }
    }
    private func switchBranch() {
        guard !session.operationBusy else { return }; session.operationBusy = true; busy = true
        Task { defer { busy = false; session.operationBusy = false }; do { try await session.saveAll(); try await GitService.checkout(branch, root: session.root); await session.refreshGit(); session.operationBusy = false; await session.externalChanges() } catch { session.present(error) } }
    }
    private func showDiff(_ file: GitFile) {
        Task { do { diff = try await GitService.run(["diff", "HEAD", "--", file.path], root: session.root); if diff.isEmpty { diff = "No tracked changes. Untracked files must be staged to appear in a Git diff." }; showingDiff = true } catch { session.present(error) } }
    }
}
