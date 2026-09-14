import SwiftUI
import TeXiumCore
import OSLog

private let buildLogger = Logger(subsystem: "app.texium.mac", category: "Compilation")

extension ProjectSession {
    func compile(scratch: Bool = false, draft: Bool = false) {
        guard !building && !operationBusy else { return }
        guard conflictPath == nil else { error = "Resolve the external file change before compiling."; return }
        guard let distribution = TeXDistribution.discover(customPath: UserDefaults.standard.string(forKey: "texPath") ?? "") else {
            error = "No local TeX installation was found. Install MacTeX or BasicTeX with latexmk, or choose your TeX binary folder in Settings → LaTeX."; return
        }
        building = true; buildStarted = Date(); buildStatus = "Saving source…"; buildLog = ""; diagnostics = []
        buildTask = Task { [weak self] in
            guard let self else { return }
            defer { self.building = false; self.buildStarted = nil }
            do {
                try await self.saveAll(); try Task.checkCancellation()
                let generation = self.sourceGeneration
                let revision = try await self.history.snapshot(label: "Automatic · before compile")
                buildLogger.info("Starting local build with \(self.configuration.engine.rawValue, privacy: .public)")
                self.buildStatus = "Typesetting with \(self.configuration.engine.title)…"
                let result = try await CompilationService.build(root: self.root, configuration: self.configuration, distribution: distribution, scratch: scratch, draft: draft) { [weak self] chunk in
                    Task { @MainActor in
                        guard let self else { return }; self.buildLog += chunk
                        if self.buildLog.utf8.count > 2_000_000 { self.buildLog = String(self.buildLog.suffix(1_000_000)) }
                    }
                }
                self.buildLog = result.log; self.diagnostics = result.diagnostics
                buildLogger.info("Local build completed with status \(result.status), \(result.diagnostics.count) diagnostics")
                if result.status == 0 {
                    self.buildStatus = "\(draft ? "Draft checked" : "Typeset") in \(String(format: "%.1f", result.elapsed)) s"
                    if let pdf = result.pdfURL {
                        self.pdfURL = pdf; self.pdfRevision = UUID(); self.builtGeneration = generation; self.stalePDF = generation != self.sourceGeneration
                        let record = BuildProvenance(revision: revision.id, date: Date(), configuration: self.configuration, sourceChangedDuringBuild: self.stalePDF)
                        let recordURL = pdf.deletingLastPathComponent().appendingPathComponent("build.json")
                        try await Task.detached { try JSONEncoder().encode(record).write(to: recordURL, options: .atomic) }.value
                    }
                } else {
                    self.buildStatus = "Build failed · \(result.status)"; self.stalePDF = self.pdfURL != nil
                    self.inspectorTab = "Problems"; self.showInspector = true
                    if self.diagnostics.isEmpty { self.diagnostics = [Diagnostic(severity: .error, message: "latexmk exited with status \(result.status). Open the full build log for details.")] }
                }
                await self.refreshHistory()
            } catch is CancellationError { self.buildStatus = "Compilation stopped"; self.stalePDF = self.pdfURL != nil; buildLogger.info("Local build cancelled") }
            catch { self.buildStatus = "Unable to compile"; self.present(error) }
        }
    }
    func stopBuild() { buildTask?.cancel() }
    func showInPDF() {
        guard let pdf = pdfURL, let file = selected, let tool = TeXDistribution.discover(customPath: UserDefaults.standard.string(forKey: "texPath") ?? "")?.tools["synctex"] else { error = "Compile with SyncTeX available before navigating to the PDF."; return }
        let line = currentLine
        Task {
            do { pdfDestination = try await SyncTeXService.forward(tool: tool, root: root, file: file, line: line, pdf: pdf); layout = "Both" }
            catch { present(error) }
        }
    }
    func showSource(at location: PDFLocation) {
        guard let pdf = pdfURL, let tool = TeXDistribution.discover(customPath: UserDefaults.standard.string(forKey: "texPath") ?? "")?.tools["synctex"] else { error = "SyncTeX is unavailable in the selected TeX distribution."; return }
        Task {
            do { let source = try await SyncTeXService.inverse(tool: tool, root: root, location: location, pdf: pdf); await select(source.file, line: source.line); layout = "Both" }
            catch { present(error) }
        }
    }
    func navigate(_ diagnostic: Diagnostic) {
        var path = diagnostic.file ?? configuration.mainFile
        if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
        if (path as NSString).isAbsolutePath { path = (try? ProjectFileSystem.relative(URL(fileURLWithPath: path), to: root)) ?? configuration.mainFile }
        Task { await select(path, line: diagnostic.line ?? 1) }
    }
    func countWords() {
        guard let distribution = TeXDistribution.discover(customPath: UserDefaults.standard.string(forKey: "texPath") ?? ""), let tool = distribution.tools["texcount"] else { error = "texcount is not installed. Install it through your TeX distribution to count LaTeX prose accurately."; return }
        Task {
            do {
                try await saveAll()
                let result = try await ProcessRunner().run(executable: tool, arguments: ["-inc", "-utf8", "./" + configuration.mainFile], directory: root, environment: distribution.environment)
                guard result.status == 0 else { throw TeXiumError.message(result.output) }
                wordReport = result.output; inspectorTab = "Statistics"; showInspector = true
            } catch { present(error) }
        }
    }
    func setShellPolicy(_ policy: ShellPolicy) {
        if policy == .enabled { shellApprovalRequested = true }
        else { configuration.shellPolicy = policy; persistPreferences() }
    }
}

private struct BuildProvenance: Codable, Sendable {
    let revision: UUID
    let date: Date
    let configuration: BuildConfiguration
    let sourceChangedDuringBuild: Bool
}
