import XCTest
@testable import TeXiumCore

final class ParserTests: XCTestCase {
    func testMatchingNestedEnvironmentsAndComments() {
        let source = "\\begin{document}\n% \\end{document}\n\\begin{itemize}\n\\item x\n\\end{itemize}\n\\end{document}"
        let ns = source as NSString
        let target = LaTeXParser.matchingEnvironment(at: ns.range(of: "\\item x").location, in: source)
        XCTAssertEqual(target.map { ns.substring(with: $0) }, "\\end{itemize}")
        XCTAssertEqual(LaTeXParser.matchingEnvironment(at: 2, in: source), ns.range(of: "\\end{document}", options: .backwards))
    }
    func testOutlinePreservesUnicodeOffsetsAndNestedTitles() {
        let source = "😀\n% \\section{Hidden}\n\\section*{A \\textbf{nested} title}\n\\subsection[Short]{Detail}"
        let outline = LaTeXParser.outline(source, file: "main.tex")
        XCTAssertEqual(outline.map(\.title), ["A \\textbf{nested} title", "Detail"])
        XCTAssertEqual(outline.map(\.line), [3, 4])
        XCTAssertEqual((source as NSString).substring(from: outline[0].offset).prefix(9), "\\section*")
        XCTAssertEqual(outline.map(\.level), [2, 3])
    }
    func testCommentEscapesAndCRLF() {
        let source = "\\% visible % hidden\r\n\\\\% hidden\r\n\\section{Visible}"
        let clean = LaTeXParser.uncomment(source)
        XCTAssertEqual((source as NSString).length, (clean as NSString).length)
        XCTAssertTrue(clean.contains("\\% visible"))
        XCTAssertFalse(clean.contains("hidden"))
        XCTAssertEqual(LaTeXParser.outline(source, file: "a.tex").first?.line, 3)
        XCTAssertEqual(LaTeXParser.offset(ofLine: 3, in: source), (source as NSString).range(of: "\\section").location)
    }
    func testCitationKeysWithOptionalArguments() {
        let source = #"\citep[see][p. 2]{alpha, beta} % \citep{ignored}"#
        XCTAssertEqual(LaTeXParser.keys(source, command: "citep"), ["alpha", "beta"])
    }
    func testMalformedOutlineIsNotInvented() {
        XCTAssertTrue(LaTeXParser.outline(#"\section{Unfinished"#, file: "a.tex").isEmpty)
    }
    func testBibTeXNestedAndQuotedValues() {
        let source = #"""
        % A reference containing nested braces and punctuation.
        @article{key:2026,
          title = {An {ABC} study, with {nested {values}}},
          author = "Xu, Dylan and Other, Author",
          year = 2026,
          journal = {A Journal},
          note = "Quoted \"text\""
        }
        @book(second, title={Second title}, year="2025")
        """#
        let entries = BibTeXParser.parse(source)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].key, "key:2026")
        XCTAssertEqual(entries[0].title, "An {ABC} study, with {nested {values}}")
        XCTAssertEqual(entries[0].author, "Xu, Dylan and Other, Author")
        XCTAssertEqual(entries[0].year, "2026")
        XCTAssertEqual(entries[1].title, "Second title")
        XCTAssertTrue(entries[0].searchText.contains("A Journal"))
    }
    func testBibTeXConcatenationAndSpecialEntries() {
        let source = "@string{journal = {Test}}\n@preamble{\"Ignored\"}\n@article{k, title = {Part } # {Two}, year=2020}"
        let entries = BibTeXParser.parse(source)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Part Two")
    }
    func testDiagnosticsWithSpacesAndLineNumbers() {
        let log = "./chapters/my file.tex:42: Undefined control sequence.\nLaTeX Warning: Reference `missing' on page 1 undefined on input line 9.\nOverfull \\hbox (1.0pt too wide) in paragraph at lines 12--13\n! Missing $ inserted.\nl.27 text\n"
        let diagnostics = DiagnosticsParser.parse(log)
        XCTAssertEqual(diagnostics.count, 4)
        XCTAssertEqual(diagnostics[0].file, "./chapters/my file.tex")
        XCTAssertEqual(diagnostics[0].line, 42)
        XCTAssertEqual(diagnostics[1].line, 9)
        XCTAssertEqual(diagnostics[2].severity, .badBox)
        XCTAssertEqual(diagnostics[3].line, 27)
    }
    func testDiagnosticDeduplication() {
        let line = "a.tex:2: Undefined control sequence."
        XCTAssertEqual(DiagnosticsParser.parse(line + "\n" + line).count, 1)
    }
    func testSyncTeXParsers() {
        let view = "SyncTeX result begin\nOutput:/tmp/a.pdf\nPage:2\nx:100.25\ny:211.5\nh:100\nv:210\nSyncTeX result end"
        XCTAssertEqual(SyncTeXService.parseView(view), PDFLocation(page: 2, x: 100.25, y: 211.5))
        let edit = "Input:/tmp/A Folder/chapter.tex\nLine:24\nColumn:0"
        XCTAssertEqual(SyncTeXService.parseEdit(edit)?.file, "/tmp/A Folder/chapter.tex")
        XCTAssertEqual(SyncTeXService.parseEdit(edit)?.line, 24)
        XCTAssertNil(SyncTeXService.parseView("Page:0\nx:no\ny:1"))
    }
    func testBuildConfigurationRoundTrip() throws {
        let config = BuildConfiguration(mainFile: "chapters/a.tex", engine: .xeLaTeX, shellPolicy: .restricted, automatic: true)
        XCTAssertEqual(try JSONDecoder().decode(BuildConfiguration.self, from: JSONEncoder().encode(config)), config)
        XCTAssertEqual(BuildConfiguration().shellPolicy, .disabled)
        XCTAssertEqual(ShellPolicy.disabled.flag, "-no-shell-escape")
    }
}
