import XCTest
@testable import TeXiumCore

class TemporaryProjectTest: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
final class FileAndHistoryTests: TemporaryProjectTest {
    func testAuxiliaryCleanupRejectsSymlinksAndPreservesPreview() throws {
        try write("source/chapter.tex", "Important source")
        let build = root.appendingPathComponent(CompilationService.buildFolder)
        try FileManager.default.createSymbolicLink(at: build, withDestinationURL: root.appendingPathComponent("source"))
        XCTAssertThrowsError(try CompilationService.clearAuxiliary(root: root))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("source/chapter.tex")), "Important source")
        try FileManager.default.removeItem(at: build)
        try write(".texium-build/main.aux", "aux")
        try write(".texium-build/preview/main.pdf", "last successful output")
        try CompilationService.clearAuxiliary(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: build.appendingPathComponent("main.aux").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: build.appendingPathComponent("preview/main.pdf").path))
    }
    func testPathsRejectTraversalAndExternalSymlinks() throws {
        XCTAssertThrowsError(try ProjectFileSystem.resolve("../secret", in: root))
        XCTAssertThrowsError(try ProjectFileSystem.resolve("/etc/passwd", in: root))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        XCTAssertThrowsError(try ProjectFileSystem.resolve("escape/passwd", in: root))
        XCTAssertEqual(try ProjectFileSystem.resolve("chapters/a.tex", in: root).lastPathComponent, "a.tex")
    }
    func testNameValidation() {
        for name in ["", ".", "..", "../x", ".git", "a/b", "a:b", "a\0b"] { XCTAssertThrowsError(try ProjectFileSystem.validateName(name), name) }
        XCTAssertNoThrow(try ProjectFileSystem.validateName("Chapter 中文.tex"))
    }
    func testUTF8BOMAndCRLFArePreserved() throws {
        let data = Data([0xef, 0xbb, 0xbf]) + Data("α\r\nsecond\r\n".utf8)
        let url = root.appendingPathComponent("main.tex"); try data.write(to: url)
        let file = try ProjectFileSystem.read(url)
        XCTAssertTrue(file.hasUTF8BOM); XCTAssertEqual(file.lineEnding, "\r\n")
        _ = try ProjectFileSystem.save(file.text + "third\r\n", file: file, to: url)
        XCTAssertEqual(try Data(contentsOf: url), data + Data("third\r\n".utf8))
    }
    func testUTF16AndUnknownEncoding() throws {
        let url = root.appendingPathComponent("utf16.tex")
        try "你好\nα".data(using: .utf16)!.write(to: url)
        let file = try ProjectFileSystem.read(url)
        XCTAssertEqual(file.encoding, .utf16); XCTAssertEqual(file.text, "你好\nα")
        _ = try ProjectFileSystem.save(file.text + "!", file: file, to: url)
        XCTAssertEqual(try ProjectFileSystem.read(url).text, "你好\nα!")
        try Data([0xff, 0x00, 0x80]).write(to: url)
        XCTAssertThrowsError(try ProjectFileSystem.read(url))
    }
    func testConflictingSaveNeverOverwritesDisk() throws {
        try write("main.tex", "Original")
        let url = root.appendingPathComponent("main.tex"); let opened = try ProjectFileSystem.read(url)
        try write("main.tex", "External edits")
        XCTAssertThrowsError(try ProjectFileSystem.save("My edits", file: opened, to: url))
        XCTAssertEqual(try String(contentsOf: url), "External edits")
    }
    func testMainDocumentAndTreeFiltering() throws {
        try write("chapters/intro.tex", "\\section{Introduction}")
        try write("main.tex", "\\documentclass{article}\n\\begin{document}\n\\end{document}")
        try write(".texium-build/main.aux", "generated")
        try write(".git/config", "metadata")
        let tree = try ProjectFileSystem.tree(at: root)
        XCTAssertEqual(ProjectFileSystem.mainDocument(in: root, files: tree), "main.tex")
        XCTAssertEqual(ProjectFileSystem.flatten(tree).map(\.path), ["chapters", "chapters/intro.tex", "main.tex"])
    }
    func testHistoryRestoreRetainsNewerVersions() async throws {
        let storage = root.appendingPathComponent(".history-test")
        let history = HistoryService(root: root, storage: storage)
        try write("main.tex", "Version one")
        let first = try await history.snapshot(label: "First")
        try write("main.tex", "Version two"); try write("new.tex", "Added later")
        _ = try await history.snapshot(label: "Second")
        try await history.restore(first)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("main.tex")), "Version one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.tex").path))
        let revisions = try await history.revisions()
        XCTAssertEqual(revisions.count, 4)
        XCTAssertTrue(revisions.contains { $0.label == "Second" })
        XCTAssertEqual(revisions.first?.label, "Restored First")
    }
    func testHistoryDeduplicatesObjectsAndDetectsCorruption() async throws {
        let storage = root.appendingPathComponent(".history-test")
        let history = HistoryService(root: root, storage: storage)
        try write("main.tex", "Same text")
        let revision = try await history.snapshot(label: "Automatic · save")
        let same = try await history.snapshot(label: "Automatic · save")
        XCTAssertEqual(same.id, revision.id)
        let object = storage.appendingPathComponent("Objects/" + revision.files["main.tex"]!)
        try Data("corrupt".utf8).write(to: object)
        do { _ = try await history.data(for: revision, file: "main.tex"); XCTFail("Expected checksum failure") } catch {}
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("main.tex")), "Same text")
    }
    func testHistoryDiff() async throws {
        let history = HistoryService(root: root, storage: root.appendingPathComponent(".history-test"))
        try write("main.tex", "one\ntwo\n"); let revision = try await history.snapshot(label: "First")
        try write("main.tex", "one\nthree\n")
        let diff = try await history.diff(revision, file: "main.tex")
        XCTAssertTrue(diff.contains("-two")); XCTAssertTrue(diff.contains("+three"))
    }
    func testSearchRegexUnicodeAndReplaceConflict() throws {
        try write("main.tex", "α cat cats CAT\ncat\n")
        let options = SearchOptions(wholeWord: true)
        let result = try SearchService.search(root: root, query: "cat", options: options)
        XCTAssertEqual(result.hits.count, 3); XCTAssertEqual(result.hits.last?.line, 2)
        try SearchService.replace(root: root, result: result, query: "cat", replacement: "$dog\\", options: options)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("main.tex")), "α $dog\\ cats $dog\\\n$dog\\\n")
        XCTAssertThrowsError(try SearchService.replace(root: root, result: result, query: "cat", replacement: "x", options: options))
        XCTAssertThrowsError(try SearchService.search(root: root, query: "[", options: SearchOptions(regex: true)))
    }
    func testTemplatesCreateOrdinaryFilesWithoutOverwriting() throws {
        for template in ProjectTemplate.allCases {
            let folder = root.appendingPathComponent(template.rawValue)
            try TemplateService.create(template, at: folder)
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("main.tex").path))
            XCTAssertThrowsError(try TemplateService.create(template, at: folder))
        }
    }
}
