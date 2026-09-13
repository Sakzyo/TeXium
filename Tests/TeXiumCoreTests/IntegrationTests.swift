import XCTest
import PDFKit
@testable import TeXiumCore

final class IntegrationTests: TemporaryProjectTest {
    func testEveryBundledTemplateCompiles() async throws {
        guard let distribution = TeXDistribution.discover(), distribution.tools["latexmk"] != nil else { throw XCTSkip("Local latexmk required") }
        for template in ProjectTemplate.allCases {
            let project = root.appendingPathComponent(template.rawValue)
            try TemplateService.create(template, at: project)
            let result = try await CompilationService.build(root: project, configuration: BuildConfiguration(), distribution: distribution)
            XCTAssertEqual(result.status, 0, "\(template.rawValue): \(result.log)")
            XCTAssertNotNil(result.pdfURL, template.rawValue)
        }
    }
    func testAlternateEnginesAndBiber() async throws {
        guard let distribution = TeXDistribution.discover(), distribution.tools["latexmk"] != nil else { throw XCTSkip("Local latexmk required") }
        for engine in [TeXEngine.xeLaTeX, .luaLaTeX, .latex] where distribution.tools[engine.rawValue] != nil {
            let project = root.appendingPathComponent(engine.rawValue)
            try TemplateService.create(.blank, at: project)
            let result = try await CompilationService.build(root: project, configuration: BuildConfiguration(engine: engine), distribution: distribution)
            XCTAssertEqual(result.status, 0, "\(engine.title): \(result.log)")
            XCTAssertNotNil(result.pdfURL)
        }
        guard distribution.tools["biber"] != nil else { throw XCTSkip("Biber is not installed") }
        let project = root.appendingPathComponent("Biber")
        try TemplateService.create(.article, at: project)
        let source = "\\documentclass{article}\n\\usepackage[backend=biber]{biblatex}\n\\addbibresource{references.bib}\n\\begin{document}\nA reference: \\cite{knuth1984}.\n\\printbibliography\n\\end{document}\n"
        try source.write(to: project.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        let result = try await CompilationService.build(root: project, configuration: BuildConfiguration(), distribution: distribution)
        XCTAssertEqual(result.status, 0, result.log)
        let pdf = try XCTUnwrap(result.pdfURL)
        XCTAssertTrue(PDFDocument(url: pdf)?.string?.contains("Donald") == true)
        XCTAssertFalse(result.diagnostics.contains { $0.message.contains("undefined") })
    }
    func testLocalCompilationBibliographyPDFAndBidirectionalSyncTeX() async throws {
        guard let distribution = TeXDistribution.discover(), distribution.tools["latexmk"] != nil else { throw XCTSkip("A local TeX distribution with latexmk is required") }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Research")
        let project = root.appendingPathComponent("Project With Spaces")
        try FileManager.default.copyItem(at: fixture, to: project)
        let marker = root.appendingPathComponent("latexmkrc-executed")
        try "system('touch \(marker.path)');\n".write(to: project.appendingPathComponent(".latexmkrc"), atomically: true, encoding: .utf8)
        let result = try await CompilationService.build(root: project, configuration: BuildConfiguration(), distribution: distribution)
        XCTAssertEqual(result.status, 0, result.log)
        let pdf = try XCTUnwrap(result.pdfURL)
        let document = try XCTUnwrap(PDFDocument(url: pdf))
        XCTAssertGreaterThanOrEqual(document.pageCount, 2)
        XCTAssertTrue(document.string?.contains("Donald") == true)
        XCTAssertNotNil(result.syncTeXURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Untrusted latexmkrc must not execute")
        let finalLog = try String(contentsOf: project.appendingPathComponent(".texium-build/main.log"))
        XCTAssertFalse(finalLog.contains("There were undefined references"))
        XCTAssertFalse(finalLog.contains("Citation `knuth1984' on page"))
        let synctex = try XCTUnwrap(distribution.tools["synctex"])
        let position = try await SyncTeXService.forward(tool: synctex, root: project, file: "chapters/methods.tex", line: 3, pdf: pdf)
        let source = try await SyncTeXService.inverse(tool: synctex, root: project, location: position, pdf: pdf)
        XCTAssertEqual(source.file, "chapters/methods.tex")
        XCTAssertGreaterThan(source.line, 0)
        // A later failure retains the exact last successful PDF bytes.
        let baseline = try Data(contentsOf: pdf)
        let main = project.appendingPathComponent("main.tex")
        let text = try String(contentsOf: main)
        try text.replacingOccurrences(of: "\\maketitle", with: "\\maketitle\n\\undefinedTeXiumCommand").write(to: main, atomically: true, encoding: .utf8)
        let failed = try await CompilationService.build(root: project, configuration: BuildConfiguration(), distribution: distribution, scratch: true)
        XCTAssertNotEqual(failed.status, 0)
        XCTAssertTrue(failed.diagnostics.contains { $0.severity == .error && $0.line != nil })
        XCTAssertEqual(try Data(contentsOf: pdf), baseline)
    }
    func testProcessPipeDrainAndCancellation() async throws {
        let runner = ProcessRunner()
        let task = Task { try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "i=0; while [ $i -lt 5000 ]; do echo output-line; i=$((i+1)); done; sleep 30 & wait"], directory: root) }
        try await Task.sleep(for: .milliseconds(250)); let start = Date(); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }
    func testCancellationBeforeLaunch() async throws {
        let runner = ProcessRunner(); runner.cancel()
        do { _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], directory: root); XCTFail("Expected cancellation") } catch is CancellationError {}
    }
    func testZIPRoundTripAndExportFiltering() async throws {
        let source = root.appendingPathComponent("source"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "Hello".write(to: source.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        try "generated".write(to: source.appendingPathComponent("main.aux"), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("project.zip")
        try await ArchiveService.export(root: source, to: archive, preset: .source)
        try ArchiveService.validateZIP(Data(contentsOf: archive))
        let destination = root.appendingPathComponent("imported")
        try await ArchiveService.importZIP(archive, to: destination)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("main.tex")), "Hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("main.aux").path))
        XCTAssertFalse(ArchiveService.include(".git/config")); XCTAssertFalse(ArchiveService.include("a.synctex.gz")); XCTAssertTrue(ArchiveService.include("figures/a.pdf"))
    }
    func testZIPRejectsMalformedAndSymlinkArchives() async throws {
        XCTAssertThrowsError(try ArchiveService.validateZIP(Data("not a zip".utf8)))
        let source = root.appendingPathComponent("source"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        let archive = root.appendingPathComponent("unsafe.zip")
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-c", "-k", source.path, archive.path], directory: root)
        XCTAssertEqual(result.status, 0)
        XCTAssertThrowsError(try ArchiveService.validateZIP(Data(contentsOf: archive)))
    }
    func testLocalGitStatusAndSafeCheckout() async throws {
        try await GitService.initialize(root: root)
        try write("a file.tex", "Source")
        let status = try await GitService.status(root: root)
        XCTAssertTrue(status.contains { $0.path == "a file.tex" && $0.status == "??" })
        do { try await GitService.checkout("other", root: root); XCTFail("Dirty checkout should be refused") } catch {}
        _ = try await GitService.run(["add", "--", "a file.tex"], root: root)
        let staged = try await GitService.status(root: root)
        XCTAssertTrue(staged.contains { $0.path == "a file.tex" && $0.status.hasPrefix("A") })
        let nested = root.appendingPathComponent("Nested"); try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        do { _ = try await GitService.status(root: nested); XCTFail("Parent repository must not be exposed for mutation") } catch {}
        do { try await GitService.initialize(root: nested); XCTFail("Nested initialization must be refused") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.appendingPathComponent(".git").path))
    }
}
