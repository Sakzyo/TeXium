import SwiftUI
import AppKit
import TeXiumCore

@MainActor @Observable final class SourceBuffer {
    let path: String
    var file: TextFile
    var text: String
    var selection = NSRange(location: 0, length: 0)
    var external: TextFile?
    var id: String { path }
    var dirty: Bool { text != file.text }
    init(path: String, file: TextFile) { self.path = path; self.file = file; text = file.text }
}
struct EditorInsertion: Equatable { let id = UUID(); let before: String; let after: String }
enum WorkspaceSheet: String, Identifiable {
    case newFile, newFolder, rename, symbols, equation, figure, table, export, search, goToLine, snapshot, note, pasteBib, customBuild, gitConnect, gitCommit
    var id: String { rawValue }
}
struct ProjectPreferences: Codable {
    var build = BuildConfiguration()
    var selected: String?
    var notes: [UserNote] = []
    var cursor = 0
    var openTabs: [String]?
    var pdfPage: Int?
    var pdfScale: Double?
    var preferredGitRemote: String?
}
@MainActor @Observable final class ProjectSession {
    static let openSessions = NSHashTable<ProjectSession>.weakObjects()
    let root: URL
    let metadata: URL
    let history: HistoryService
    var nodes: [ProjectFile] = []
    var buffers: [String: SourceBuffer] = [:]
    var tabs: [String] = []
    var selected: String?
    var outline: [OutlineItem] = []
    var references: [BibEntry] = []
    var labels: [String] = []
    @ObservationIgnored var completionProject = CompletionProject()
    var configuration = BuildConfiguration()
    var notes: [UserNote] = []
    var revisions: [Revision] = []
    var error: String?
    var notice: String?
    var loaded = false
    var showInspector = true
    var inspectorTab = "Outline"
    var layout = "Both"
    var showNavigator = true
    var sheet: WorkspaceSheet?
    var renamePath: String?
    var deletePath: String?
    var insertion: EditorInsertion?
    var navigationID = UUID()
    var buildTask: Task<Void, Never>?
    var building = false
    var buildStarted: Date?
    var buildStatus = "Ready to typeset"
    var buildLog = ""
    var diagnostics: [Diagnostic] = []
    var pdfURL: URL?
    var pdfRevision = UUID()
    var pdfDestination: PDFLocation?
    var savedPDFPage = 1
    var savedPDFScale = 0.0
    var stalePDF = false
    var sourceGeneration = 0
    var builtGeneration = -1
    var wordReport = ""
    var gitFiles: [GitFile] = []
    var gitBranch = ""
    var isGitRepository = false
    var gitState: GitRepositoryState?
    var preferredGitRemote: String?
    var gitTask: Task<Void, Never>?
    var gitMessage = ""
    var gitLog = ""
    var gitFailed = false
    var gitLastFetched: Date?
    var gitRefreshID = UUID()
    var historyDiff = ""
    var conflictPath: String?
    var recoveryAvailable: [String: String] = [:]
    var shellApprovalRequested = false
    var operationBusy = false
    @ObservationIgnored var saveTask: Task<Void, Error>?
    @ObservationIgnored var autosaveTask: Task<Void, Never>?
    @ObservationIgnored var automaticBuildTask: Task<Void, Never>?
    @ObservationIgnored var indexTask: Task<Void, Never>?
    @ObservationIgnored private let recoveryWriter = RecoveryWriter()
    @ObservationIgnored private var recoveryGeneration = 0
    @ObservationIgnored var monitor: ProjectMonitor?
    @ObservationIgnored var scopedAccess = false
    @ObservationIgnored weak var editor: LaTeXTextView?
    @ObservationIgnored weak var pdfView: SyncedPDFView?
    var currentBuffer: SourceBuffer? { selected.flatMap { buffers[$0] } }
    var files: [ProjectFile] { ProjectFileSystem.flatten(nodes).filter { !$0.isDirectory } }
    var currentLine: Int { currentBuffer.map { LaTeXParser.lineNumber(at: $0.selection.location, in: $0.text) } ?? 1 }
    var title: String { root.lastPathComponent }

    init(root: URL) {
        self.root = root; metadata = ProjectFileSystem.metadataDirectory(for: root); history = HistoryService(root: root)
        Self.openSessions.add(self)
    }
    func load() async {
        guard !loaded else { return }; loaded = true
        scopedAccess = root.startAccessingSecurityScopedResource()
        do {
            let root = root; let metadata = metadata
            let (tree, prefs, recovery) = try await Task.detached {
                try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
                let tree = try ProjectFileSystem.tree(at: root)
                let prefs = (try? JSONDecoder().decode(ProjectPreferences.self, from: Data(contentsOf: metadata.appendingPathComponent("project.json"))))
                let savedRecovery = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: metadata.appendingPathComponent("recovery.json")))) ?? [:]
                let recovery = savedRecovery.filter { path, text in
                    (try? ProjectFileSystem.read(ProjectFileSystem.resolve(path, in: root)).text) != text
                }
                return (tree, prefs, recovery)
            }.value
            nodes = tree
            if let prefs {
                configuration = prefs.build; notes = prefs.notes; preferredGitRemote = prefs.preferredGitRemote
                savedPDFPage = prefs.pdfPage ?? 1; savedPDFScale = prefs.pdfScale ?? 0
                for path in prefs.openTabs ?? [] where FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) { await select(path) }
            }
            else {
                configuration.mainFile = await Task.detached { ProjectFileSystem.mainDocument(in: root, files: tree) ?? "main.tex" }.value
                configuration.engine = TeXEngine(rawValue: UserDefaults.standard.string(forKey: "defaultEngine") ?? "pdflatex") ?? .pdfLaTeX
            }
            let target = prefs?.selected ?? configuration.mainFile
            await select(target, line: nil)
            if let cursor = prefs?.cursor, let buffer = currentBuffer { buffer.selection = NSRange(location: min(cursor, (buffer.text as NSString).length), length: 0) }
            recoveryAvailable = recovery
            let preview = root.appendingPathComponent(CompilationService.buildFolder + "/preview/" + (configuration.mainFile as NSString).lastPathComponent).deletingPathExtension().appendingPathExtension("pdf")
            if FileManager.default.fileExists(atPath: preview.path) { pdfURL = preview; stalePDF = true }
            await refreshIndex(); await refreshHistory(); await refreshGit()
            monitor = ProjectMonitor(root: root) { [weak self] in Task { @MainActor in await self?.externalChanges() } }
        } catch { self.error = error.localizedDescription }
    }
    func select(_ path: String, line: Int? = nil) async {
        do {
            let url = try ProjectFileSystem.resolve(path, in: root)
            if ProjectFileSystem.textExtensions.contains(url.pathExtension.lowercased()) {
                if buffers[path] == nil {
                    let file = try await Task.detached { try ProjectFileSystem.read(url) }.value
                    buffers[path] = SourceBuffer(path: path, file: file)
                }
                if !tabs.contains(path) { tabs.append(path) }
                if let line, let buffer = buffers[path] { buffer.selection = NSRange(location: LaTeXParser.offset(ofLine: line, in: buffer.text), length: 0); navigationID = UUID() }
            }
            selected = path; persistPreferences()
        } catch { self.error = error.localizedDescription }
    }
    func edited(_ buffer: SourceBuffer) {
        sourceGeneration += 1; stalePDF = pdfURL != nil
        writeRecovery()
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)); try await self?.saveAll(); await self?.refreshIndex(); await self?.refreshGit() }
            catch is CancellationError {} catch { self?.present(error) }
        }
        if configuration.automatic { scheduleAutomaticBuild() }
    }
    func scheduleAutomaticBuild() {
        automaticBuildTask?.cancel()
        automaticBuildTask = Task { [weak self] in
            let delay = max(1, UserDefaults.standard.double(forKey: "autoCompileDelay"))
            do { try await Task.sleep(for: .seconds(delay)); guard let self, self.configuration.automatic else { return }; if self.building { self.stopBuild(); if let task = self.buildTask { await task.value } }; self.compile() } catch {}
        }
    }
    func saveAll() async throws {
        if let task = saveTask { try await task.value; return try await saveAll() }
        let dirty = buffers.values.filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let writes = try dirty.map { ($0.path, $0.text, $0.file, try ProjectFileSystem.resolve($0.path, in: root)) }
        let task = Task { @MainActor in
            for (path, text, file, url) in writes {
                let saved = try await Task.detached { try ProjectFileSystem.save(text, file: file, to: url) }.value
                buffers[path]?.file = saved
            }
            writeRecovery(); persistPreferences()
        }
        saveTask = task
        do { try await task.value } catch { saveTask = nil; throw error }
        saveTask = nil
        // An edit made during coordinated disk IO remains dirty against the
        // newly saved baseline and must be included before a build or file move.
        if buffers.values.contains(where: \.dirty) { try await saveAll() }
    }
    func saveAllSynchronously() throws {
        // Used only at the AppKit close/quit boundary where returning before disk
        // completion could discard the window and its recovery state.
        guard saveTask == nil else { throw TeXiumError.message("A save is still in progress. Please try closing again after it finishes.") }
        for buffer in buffers.values where buffer.dirty {
            buffer.file = try ProjectFileSystem.save(buffer.text, file: buffer.file, to: ProjectFileSystem.resolve(buffer.path, in: root))
        }
        writeRecovery(); persistPreferences()
    }
    func persistPreferences() {
        let preferences = ProjectPreferences(build: configuration, selected: selected, notes: notes, cursor: currentBuffer?.selection.location ?? 0, openTabs: tabs, pdfPage: savedPDFPage, pdfScale: savedPDFScale, preferredGitRemote: preferredGitRemote)
        do { try JSONEncoder().encode(preferences).write(to: metadata.appendingPathComponent("project.json"), options: .atomic) }
        catch { notice = "Project preferences could not be saved: " + error.localizedDescription }
    }
    func writeRecovery() {
        let dirty = Dictionary(uniqueKeysWithValues: buffers.values.filter(\.dirty).map { ($0.path, $0.text) })
        recoveryGeneration += 1
        let generation = recoveryGeneration; let url = metadata.appendingPathComponent("recovery.json")
        Task {
            do { try await recoveryWriter.write(dirty, generation: generation, to: url) }
            catch { self.error = "Recovery could not be saved: " + error.localizedDescription }
        }
    }
    func recoverBuffers() async {
        for (path, text) in recoveryAvailable { await select(path); if let buffer = buffers[path] { buffer.text = text; edited(buffer) } }
        recoveryAvailable = [:]
    }
    func refreshIndex() async {
        let root = root; let live = Dictionary(uniqueKeysWithValues: buffers.values.map { ($0.path, $0.text) })
        do {
            let result = try await Task.detached { () -> ([ProjectFile], [OutlineItem], [BibEntry], [String], CompletionProject) in
                let nodes = try ProjectFileSystem.tree(at: root)
                var outline: [OutlineItem] = []; var references: [BibEntry] = []; var labels: [String] = []
                var completionProject = CompletionProject()
                for file in ProjectFileSystem.flatten(nodes) where ["tex", "bib", "sty", "cls"].contains((file.path as NSString).pathExtension.lowercased()) {
                    let text = live[file.path] ?? ((try? ProjectFileSystem.read(ProjectFileSystem.resolve(file.path, in: root)).text) ?? "")
                    completionProject.update(text, file: file.path)
                    if file.path.hasSuffix(".bib") { references += BibTeXParser.parse(text, file: file.path) }
                    else { outline += LaTeXParser.outline(text, file: file.path); labels += LaTeXParser.keys(text, command: "label") }
                }
                return (nodes, outline, references, labels, completionProject)
            }.value
            nodes = result.0; outline = result.1; references = result.2; labels = result.3
            completionProject = result.4; editor?.completionController.refreshIfVisible()
        } catch { self.error = error.localizedDescription }
    }
    func externalChanges() async {
        guard !operationBusy else { return }
        if let saveTask { _ = try? await saveTask.value }
        let root = root; let paths = Array(buffers.keys)
        let disk = await Task.detached {
            Dictionary(uniqueKeysWithValues: paths.compactMap { path -> (String, TextFile)? in
                guard let file = try? ProjectFileSystem.read(ProjectFileSystem.resolve(path, in: root)) else { return nil }; return (path, file)
            })
        }.value
        for path in paths {
            guard let buffer = buffers[path] else { continue }
            guard let external = disk[path] else { buffer.external = nil; conflictPath = path; continue }
            guard external.baseline != buffer.file.baseline else { continue }
            if buffer.dirty { buffer.external = external; conflictPath = path }
            else { buffer.file = external; buffer.text = external.text; sourceGeneration += 1; stalePDF = pdfURL != nil }
        }
        await refreshIndex(); await refreshGit()
    }
    func resolveConflict(useDisk: Bool) async {
        guard let path = conflictPath, let buffer = buffers[path] else { return }
        if useDisk {
            guard let external = buffer.external else { error = "The external file is missing. Export your current buffer before closing it."; return }
            buffer.text = external.text; buffer.file = external
        } else {
            // Explicit keep-mine action first retains the external state in history.
            do {
                _ = try await history.snapshot(label: "Before resolving external change")
                let url = try ProjectFileSystem.resolve(path, in: root)
                if FileManager.default.fileExists(atPath: url.path) {
                    buffer.file = try await Task.detached { try ProjectFileSystem.read(url) }.value
                    try await saveAll()
                } else {
                    let text = buffer.text; let file = buffer.file
                    buffer.file = try await Task.detached {
                        try file.encoded(text).write(to: url, options: .withoutOverwriting)
                        return try ProjectFileSystem.read(url)
                    }.value
                }
            } catch { present(error); return }
        }
        buffer.external = nil; conflictPath = nil; writeRecovery()
    }
    func present(_ error: Error) {
        if case TeXiumError.conflict = error { Task { await externalChanges() } }
        else { self.error = error.localizedDescription }
    }
    func insert(_ before: String, after: String = "") { guard !operationBusy else { return }; insertion = EditorInsertion(before: before, after: after) }
    func closeTab(_ path: String) {
        Task {
            do { try await saveAll(); tabs.removeAll { $0 == path }; buffers.removeValue(forKey: path); if selected == path { selected = tabs.last } }
            catch { present(error) }
        }
    }
    func refreshHistory() async { do { revisions = try await history.revisions() } catch { present(error) } }
    func snapshot(_ label: String) async {
        do { try await saveAll(); _ = try await history.snapshot(label: label); await refreshHistory() } catch { present(error) }
    }
    func shutdown() {
        Self.openSessions.remove(self)
        gitTask?.cancel(); stopBuild(); autosaveTask?.cancel(); automaticBuildTask?.cancel(); monitor?.stop(); monitor = nil
        if scopedAccess { root.stopAccessingSecurityScopedResource(); scopedAccess = false }
    }
}
