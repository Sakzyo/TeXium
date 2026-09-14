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
            if session.revisions.isEmpty {
                InspectorEmptyState(title: "No Snapshots Yet", symbol: "clock.arrow.circlepath", message: "Take a snapshot to save a local version of this project.")
            } else {
                List(session.revisions, selection: $selected) { revision in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(revision.label, systemImage: "clock.arrow.circlepath").font(.callout)
                        Text(revision.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Text("\(revision.files.count) files").font(.caption).foregroundStyle(.tertiary)
                    }.tag(revision.id).padding(.vertical, 3)
                }.listStyle(.inset)
            }
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
