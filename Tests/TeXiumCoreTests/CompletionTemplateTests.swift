import XCTest
import PDFKit
@testable import TeXiumCore

final class CompletionTemplateTests: XCTestCase {
    private func complete(_ marked: String, name: String, formatting: CompletionFormatting? = nil) throws -> (String, CompletionItem, Int) {
        let cursor = (marked as NSString).range(of: "¦").location
        let source = marked.replacingOccurrences(of: "¦", with: "")
        let result = try XCTUnwrap(LaTeXCompletion.suggestions(in: source, at: cursor, file: "main.tex", project: .init(), formatting: formatting))
        let item = try XCTUnwrap(result.items.first { $0.title == name })
        return ((source as NSString).replacingCharacters(in: result.range, with: item.insertion), item, result.range.location)
    }
    private func values(_ item: CompletionItem) -> [String] {
        item.fields.map { (item.insertion as NSString).substring(with: $0) }
    }

    func testFigureInsertsCompleteStructureWithSelectedDefaults() throws {
        let (source, item, _) = try complete(#"\begin{fig¦}"#, name: "figure")
        XCTAssertEqual(source, #"""
        \begin{figure}
            \centering
            \includegraphics[width=0.5\linewidth]{}
            \caption{Caption}
            \label{fig:placeholder}
        \end{figure}
        """#)
        XCTAssertEqual(values(item), ["", "Caption", "fig:placeholder", ""])
        XCTAssertEqual(item.stops.last, (item.insertion as NSString).length)
        XCTAssertTrue(item.detail.contains("graphicx"))
    }
    func testListsStartAtFirstItemAndDescriptionHasTerm() throws {
        for name in ["enumerate", "itemize"] {
            let (source, item, base) = try complete("\\begin{\(name)¦}", name: name)
            XCTAssertEqual(source, "\\begin{\(name)}\n    \\item \n\\end{\(name)}")
            XCTAssertEqual((source as NSString).substring(to: base + item.stops[0]), "\\begin{\(name)}\n    \\item ")
        }
        let (source, item, _) = try complete(#"\begin{desc¦}"#, name: "description")
        XCTAssertTrue(source.contains(#"\item[] "#))
        XCTAssertEqual(values(item), ["", "", ""])
    }
    func testMissingOrAlreadyTypedClosingBraceProducesOnePair() throws {
        let expected = "\\begin{itemize}\n    \\item \n\\end{itemize}"
        for marked in [#"\begin{item¦"#, #"\begin{item¦}"#, #"\begin{item}¦"#, #"\begin{it¦emize}"#, #"\begin{item¦  }"#] {
            XCTAssertEqual(try complete(marked, name: "itemize").0, expected, marked)
        }
    }
    func testEndCompletionOnlyChangesTheName() throws {
        let (source, item, _) = try complete("\\begin{figure}\nExisting image\n\\end{fig¦}", name: "figure")
        XCTAssertEqual(source, "\\begin{figure}\nExisting image\n\\end{figure}")
        XCTAssertTrue(item.fields.isEmpty)
    }
    func testExistingOptionsBodiesAndEndsArePreserved() throws {
        for suffix in ["[htbp]\nImage", "\n    Existing image\n\\end{figure}", "\n\\begin{center}\nImage\n\\end{center}\n\\end{figure}", "\n\\end{figure}", " % keep comment\n"] {
            let (source, item, _) = try complete("\\begin{fig¦}" + suffix, name: "figure")
            XCTAssertEqual(source, "\\begin{figure}" + suffix)
            XCTAssertTrue(item.fields.isEmpty)
        }
        XCTAssertEqual(try complete(#"\begin{tab¦}{lcr}"#, name: "tabular").0, #"\begin{tabular}{lcr}"#)
        XCTAssertEqual(try complete("\\begin{figur¦e  }\n\\end{figure}", name: "figure").0, "\\begin{figure  }\n\\end{figure}")
    }
    func testNestedNewEnvironmentDoesNotReuseOuterEnd() throws {
        let (source, _, _) = try complete("\\begin{itemize}\n    \\item Outer\n    \\begin{item¦}\n\\end{itemize}", name: "itemize")
        XCTAssertEqual(source, "\\begin{itemize}\n    \\item Outer\n    \\begin{itemize}\n        \\item \n    \\end{itemize}\n\\end{itemize}")
        let existing = "\\begin{itemize}\n    \\item Outer\n    \\begin{item¦}\n        \\item Existing\n    \\end{itemize}\n\\end{itemize}"
        XCTAssertEqual(try complete(existing, name: "itemize").0, existing.replacingOccurrences(of: "item¦", with: "itemize"))
        let (different, _, _) = try complete("\\begin{document}\n\\begin{enum¦}\n\\end{document}\n\\begin{enumerate}\nLater\n\\end{enumerate}", name: "enumerate")
        XCTAssertTrue(different.contains("\\begin{enumerate}\n    \\item \n\\end{enumerate}\n\\end{document}"))
    }
    func testIndentationCRLFAndUTF16Fields() throws {
        let (source, item, base) = try complete("% 😀\r\n\t\\begin{fig¦}\r\n", name: "figure", formatting: .init(indentation: "\t", lineEnding: "\r\n"))
        XCTAssertTrue(source.contains("\r\n\t\t\\caption{Caption}\r\n\t\t\\label{fig:placeholder}\r\n\t\\end{figure}\r\n"))
        XCTAssertFalse(source.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        XCTAssertEqual((source as NSString).substring(with: NSRange(location: base + item.fields[1].location, length: item.fields[1].length)), "Caption")
        XCTAssertTrue(try complete("\r\n  \\begin{enum¦}", name: "enumerate", formatting: .init(indentation: "  ", lineEnding: "\r\n")).0.contains("\r\n    \\item "))
        XCTAssertTrue(try complete("\r\n\\begin{enum¦}", name: "enumerate").1.insertion.contains("\r\n"))
    }
    func testTablesMatricesAndParameterizedEnvironments() throws {
        let table = try complete(#"\begin{table¦}"#, name: "table").1
        XCTAssertEqual(values(table), ["htbp", "c|c", "", "", "", "", "Caption", "tab:placeholder", ""])
        XCTAssertTrue(table.insertion.contains("\\end{tabular}"))
        for name in ["array", "tabular", "pmatrix", "cases"] {
            let item = try complete("\\begin{\(name)¦}", name: name).1
            XCTAssertTrue(item.insertion.contains(" &  \\\\\n"), name)
            XCTAssertTrue(item.insertion.hasSuffix("\\end{\(name)}"))
        }
        XCTAssertEqual(values(try complete(#"\begin{frame¦}"#, name: "frame").1), ["Frame Title", "", ""])
        XCTAssertEqual(values(try complete(#"\begin{minipage¦}"#, name: "minipage").1), [#"0.5\linewidth"#, "", ""])
        XCTAssertEqual(values(try complete(#"\begin{tabularx¦}"#, name: "tabularx").1), [#"\linewidth"#, "XX", "", "", "", "", ""])
    }
    func testAllCatalogTemplatesHaveValidOrderedFieldsAndFinalStop() throws {
        for name in CompletionCatalog.environments {
            let (source, item, _) = try complete("\\begin{\(name)¦}", name: name)
            XCTAssertFalse(source.contains("«")); XCTAssertFalse(source.contains("»"))
            XCTAssertTrue(source.hasSuffix("\\end{\(name)}"), name)
            XCTAssertEqual(item.fields.last, NSRange(location: (item.insertion as NSString).length, length: 0))
            for pair in zip(item.fields, item.fields.dropFirst()) { XCTAssertLessThanOrEqual(NSMaxRange(pair.0), pair.1.location, name) }
        }
    }
    func testOptionalCommandArgumentsAndExistingOptions() throws {
        let image = try complete(#"\includegr¦"#, name: #"\includegraphics[width]{file}"#).1
        XCTAssertEqual(values(image), [#"0.5\linewidth"#, "", ""])
        XCTAssertEqual(image.insertion, #"\includegraphics[width=0.5\linewidth]{}"#)
        let existing = try complete(#"\includegr¦[height=2cm]{photo.pdf}"#, name: #"\includegraphics[width]{file}"#)
        XCTAssertEqual(existing.0, #"\includegraphics[height=2cm]{photo.pdf}"#)
        XCTAssertTrue(existing.1.fields.isEmpty)
        let document = try complete(#"\documentcl¦"#, name: #"\documentclass[options]{class}"#).1
        XCTAssertEqual(document.insertion, #"\documentclass[]{article}"#)
        XCTAssertEqual(values(document), ["", "article", ""])
    }
    func testFieldNavigationAfterReplacingDefaultsAndUnicode() throws {
        let (_, item, base) = try complete(#"\begin{fig¦}"#, name: "figure")
        var session = try XCTUnwrap(CompletionSnippetSession(fields: item.fields, base: base))
        var source = "\\begin{" + item.insertion
        func replace(_ text: String) {
            let range = session.selection
            XCTAssertTrue(session.replace(range, with: text))
            source = (source as NSString).replacingCharacters(in: range, with: text)
            XCTAssertTrue(session.trackSelection(NSRange(location: range.location + (text as NSString).length, length: 0)))
        }
        replace("images/😀.pdf")
        _ = session.advance(backwards: false)
        XCTAssertEqual((source as NSString).substring(with: session.selection), "Caption")
        replace("A longer caption")
        _ = session.advance(backwards: false)
        XCTAssertEqual((source as NSString).substring(with: session.selection), "fig:placeholder")
        _ = session.advance(backwards: true)
        XCTAssertEqual((source as NSString).substring(with: session.selection), "A longer caption")
        replace("Short")
        _ = session.advance(backwards: false); replace("fig:short")
        _ = session.advance(backwards: false)
        XCTAssertTrue(session.isAtEnd)
        XCTAssertEqual(session.selection.location, (source as NSString).length)
        XCTAssertFalse(session.replace(NSRange(location: 0, length: 1), with: ""))
        XCTAssertFalse(session.trackSelection(NSRange(location: 0, length: 0)))
    }

    func testCompletedTemplatesCompileToPDF() async throws {
        guard let distribution = TeXDistribution.discover(), distribution.tools["latexmk"] != nil else { throw XCTSkip("Local latexmk required") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-Snippet-Compile-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Research/figures/study.png")
        try FileManager.default.copyItem(at: image, to: root.appendingPathComponent("study.png"))
        func filled(_ name: String, _ values: [String]) throws -> String {
            let (_, item, _) = try complete("\\begin{\(name)¦}", name: name)
            XCTAssertEqual(values.count, item.fields.count - 1)
            var text = item.insertion
            for (field, value) in zip(item.fields, values).reversed() { text = (text as NSString).replacingCharacters(in: field, with: value) }
            return "\\begin{" + text
        }
        let body = try [
            filled("figure", ["study.png", "Template figure", "fig:sample"]),
            filled("itemize", ["Bullet item"]),
            filled("enumerate", ["Numbered item"]),
            filled("description", ["Term", "Description text"]),
            filled("table", ["htbp", "c|c", "A", "B", "1", "2", "Template table", "tab:sample"]),
            filled("tabularx", [#"\linewidth"#, "XX", "Left", "Right", "One", "Two"]),
            filled("equation", [#"\frac{a}{b}"#]),
            "\\[" + filled("pmatrix", ["1", "0", "0", "1"]) + "\\]",
            filled("minipage", [#"0.5\linewidth"#, "Minipage text"])
        ].joined(separator: "\n\n")
        try ("\\documentclass{article}\n\\usepackage{graphicx,amsmath,tabularx}\n\\begin{document}\n" + body + "\n\\end{document}\n").write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        let result = try await CompilationService.build(root: root, configuration: BuildConfiguration(), distribution: distribution)
        XCTAssertEqual(result.status, 0, result.log)
        let pdf = try XCTUnwrap(result.pdfURL)
        let text = try XCTUnwrap(PDFDocument(url: pdf)?.string)
        for expected in ["Template figure", "Bullet item", "Numbered item", "Template table", "Minipage text"] { XCTAssertTrue(text.contains(expected), expected) }
        try ("\\documentclass{beamer}\n\\begin{document}\n" + filled("frame", ["Template frame", "Frame body"]) + "\n\\end{document}\n").write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        let slides = try await CompilationService.build(root: root, configuration: BuildConfiguration(), distribution: distribution)
        XCTAssertEqual(slides.status, 0, slides.log)
        XCTAssertTrue(PDFDocument(url: try XCTUnwrap(slides.pdfURL))?.string?.contains("Template frame") == true)
    }
}
