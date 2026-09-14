import SwiftUI
import AppKit
import TeXiumCore

struct WorkspaceSheets: View {
    @Bindable var session: ProjectSession
    let sheet: WorkspaceSheet
    @State private var text = ""
    @State private var line = 1
    @State private var preset = ExportPreset.source
    @State private var sourceFolder = false
    @State private var busy = false
    var body: some View {
        switch sheet {
        case .gitConnect: GitHubConnectionSheet(session: session)
        case .gitCommit: GitCommitSheet(session: session)
        case .symbols: SymbolPalette(session: session)
        case .equation: EquationAssistant(session: session)
        case .figure: FigureAssistant(session: session)
        case .table: TableAssistant(session: session)
        case .search: ProjectSearchSheet(session: session)
        case .export: exportSheet
        case .pasteBib: bibSheet
        case .customBuild: CustomBuildSheet(session: session)
        default: simpleSheet
        }
    }
    private var title: String {
        switch sheet {
        case .newFile: "New File"
        case .newFolder: "New Folder"
        case .rename: "Rename Item"
        case .goToLine: "Go to Line"
        case .snapshot: "Take a Snapshot"
        case .note: "Personal Note"
        default: "TeXium"
        }
    }
    private var simpleSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.weight(.semibold))
            if sheet == .goToLine { TextField("Line number", value: $line, format: .number) }
            else if sheet == .note {
                Text("\(session.selected ?? "Project note") · Line \(session.currentLine)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.body).frame(height: 150).border(Color.secondary.opacity(0.2))
            } else { TextField(sheet == .snapshot ? "Snapshot label" : "Name", text: $text) }
            if sheet == .newFile || sheet == .newFolder { Text("In \(session.selectedFolder.isEmpty ? session.title : session.selectedFolder)").font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Cancel") { session.sheet = nil }.keyboardShortcut(.cancelAction); Button(sheet == .goToLine ? "Go" : "Save") { submit() }.keyboardShortcut(.defaultAction).disabled(sheet != .goToLine && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 440)
        .onAppear { if sheet == .rename { text = (session.renamePath as NSString?)?.lastPathComponent ?? "" }; if sheet == .snapshot { text = "Writing milestone" }; if sheet == .newFile { text = "untitled.tex" }; line = session.currentLine }
    }
    private func submit() {
        switch sheet {
        case .newFile: Task { await session.createItem(name: text, folder: false) }
        case .newFolder: Task { await session.createItem(name: text, folder: true) }
        case .rename: if let path = session.renamePath { Task { await session.renameItem(path, to: text) } }
        case .goToLine: if let path = session.selected { Task { await session.select(path, line: max(1, line)) } }; session.sheet = nil
        case .snapshot: let label = text; Task { await session.snapshot(label) }; session.sheet = nil
        case .note: session.notes.append(UserNote(text: text, file: session.selected, line: session.currentLine)); session.persistPreferences(); session.sheet = nil; session.inspectorTab = "Notes"
        default: break
        }
    }
    private var exportSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export Project").font(.title2.weight(.semibold))
            Picker("Include", selection: $preset) { ForEach(ExportPreset.allCases) { Text($0.rawValue).tag($0) } }
            Toggle("Export as a folder instead of ZIP", isOn: $sourceFolder)
            Text(preset == .submission ? "Includes source, figures, bibliography files, and generated .bbl files when available. Review your destination’s submission rules before uploading." : "Build caches, version-control data, and unrelated auxiliary files are omitted from source exports.").font(.callout).foregroundStyle(.secondary)
            if busy { ProgressView() }
            HStack { Spacer(); Button("Cancel") { session.sheet = nil }; Button("Export…") { export() }.keyboardShortcut(.defaultAction).disabled(busy) }
        }.padding(24).frame(width: 480)
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = session.title + (sourceFolder ? " Source" : ".zip")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = session.root; let preset = preset; let zip = !sourceFolder; busy = true
        Task { defer { busy = false }; do { try await session.saveAll(); try await Task.detached { try await ArchiveService.export(root: root, to: url, preset: preset, zip: zip) }.value; session.sheet = nil; NSWorkspace.shared.activateFileViewerSelecting([url]) } catch { session.present(error) } }
    }
    private var bibSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste BibTeX").font(.title2.weight(.semibold))
            Text("Entries are appended to references.bib. Existing duplicate keys are left unchanged.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 280)
            Text("\(BibTeXParser.parse(text).count) entries detected").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { session.sheet = nil }; Button("Add Entries") { addBib() }.disabled(BibTeXParser.parse(text).isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 620)
    }
    private func addBib() {
        let pasted = text
        Task {
            do {
                try await session.saveAll(); _ = try await session.history.snapshot(label: "Before adding bibliography entries")
                let target = try ProjectFileSystem.resolve("references.bib", in: session.root)
                let existing = FileManager.default.fileExists(atPath: target.path) ? try ProjectFileSystem.read(target) : nil
                let keys = Set(BibTeXParser.parse(existing?.text ?? "").map(\.key))
                let entries = BibTeXParser.parse(pasted).filter { !keys.contains($0.key) }
                guard !entries.isEmpty else { throw TeXiumError.message("All pasted citation keys already exist.") }
                // Preserve the user's original pasted syntax when there are no
                // duplicates; otherwise require explicit cleanup instead of rewriting.
                guard entries.count == BibTeXParser.parse(pasted).count else { throw TeXiumError.message("Some pasted keys already exist. Remove duplicates before importing so your BibTeX syntax can be preserved exactly.") }
                let content = (existing?.text ?? "") + "\n" + pasted + "\n"
                if let existing { _ = try ProjectFileSystem.save(content, file: existing, to: target) }
                else { try content.write(to: target, atomically: true, encoding: .utf8) }
                await session.externalChanges(); session.sheet = nil; session.inspectorTab = "References"
            } catch { session.present(error) }
        }
    }
}

struct ConflictSheet: View {
    @Bindable var session: ProjectSession
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This File Changed Outside TeXium").font(.title2.weight(.semibold))
            Text(session.conflictPath ?? "").font(.callout).foregroundStyle(.secondary)
            Text("Choose which version to keep. Keeping your edits creates a snapshot of the external version first.").font(.callout)
            HSplitView {
                VStack(alignment: .leading) { Text("Your Edits").font(.headline); NativeTextDisplay(text: session.conflictPath.flatMap { session.buffers[$0]?.text } ?? "") }
                VStack(alignment: .leading) { Text("On Disk").font(.headline); NativeTextDisplay(text: session.conflictPath.flatMap { session.buffers[$0]?.external?.text } ?? "The file is missing or unavailable.") }
            }
            HStack { Spacer(); Button("Use Disk Version") { Task { await session.resolveConflict(useDisk: true) } }.disabled(session.conflictPath.flatMap { session.buffers[$0]?.external } == nil); Button("Keep My Edits") { Task { await session.resolveConflict(useDisk: false) } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 940, height: 600)
    }
}

struct CustomBuildSheet: View {
    @Bindable var session: ProjectSession
    @State private var executable = ""
    @State private var arguments = "[]"
    @State private var approval = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Build Command").font(.title2.weight(.semibold))
            TextField("Absolute executable path", text: $executable)
            TextField("Arguments as a JSON array", text: $arguments)
            Text("The executable runs in the project folder with your account’s permissions. Arguments are passed directly, without a shell. Output appears in the Build Log.").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { session.sheet = nil }; Button("Review and Run…") { approval = true }.disabled(executable.isEmpty || session.building || session.operationBusy) }
        }.padding(24).frame(width: 600)
        .alert("Run This Executable?", isPresented: $approval) {
            Button("Cancel", role: .cancel) {}
            Button("Run Command") { run() }
        } message: { Text(executable + "\n" + arguments + "\nWorking directory: " + session.root.path) }
    }
    private func run() {
        do {
            guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else { throw TeXiumError.message("Choose an existing executable using its absolute path.") }
            let args = try JSONDecoder().decode([String].self, from: Data(arguments.utf8)); let tool = URL(fileURLWithPath: executable)
            session.sheet = nil; session.building = true; session.buildStatus = "Running custom command…"; session.buildLog = ""; session.inspectorTab = "Build Log"
            session.buildTask = Task {
                defer { session.building = false }
                do { try await session.saveAll(); let result = try await ProcessRunner().run(executable: tool, arguments: args, directory: session.root) { [weak session] chunk in Task { @MainActor in session?.buildLog += chunk } }; session.buildLog = result.output; session.buildStatus = "Custom command exited: \(result.status)" }
                catch is CancellationError { session.buildStatus = "Custom command stopped" }
                catch { session.present(error) }
            }
        } catch { session.present(error) }
    }
}
