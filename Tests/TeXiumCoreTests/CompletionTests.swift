import XCTest
@testable import TeXiumCore

final class CompletionTests: XCTestCase {
    private var project: CompletionProject {
        var project = CompletionProject()
        project.update("\\section{Introduction to topology}\n\\label{sec:intro}\n\\section{Results}\n\\label{sec:results}\n% \\label{hidden}\n", file: "chapters/intro.tex")
        project.update("@book{knuth1984, title={The TeXbook}, author={Donald Knuth}, year={1984}}\n@article{doe2025, title={Topology of surfaces}, author={Jane Doe}, year={2025}}", file: "references.bib")
        return project
    }
    private func request(_ marked: String, project: CompletionProject? = nil, live: [String: String] = [:], files: [String] = [], explicit: Bool = false) throws -> CompletionResult {
        let source = marked.replacingOccurrences(of: "|", with: "")
        let cursor = (marked as NSString).range(of: "|").location
        return try XCTUnwrap(LaTeXCompletion.suggestions(in: source, at: cursor, file: "main.tex", project: project ?? self.project, liveBuffers: live, files: files, explicit: explicit))
    }
    private func apply(_ item: CompletionItem, result: CompletionResult, to marked: String) -> String {
        let source = marked.replacingOccurrences(of: "|", with: "") as NSString
        return source.replacingCharacters(in: result.range, with: item.insertion)
    }

    func testCommandSnippetsAndArgumentStops() throws {
        let result = try request(#"\fra|"#)
        let item = try XCTUnwrap(result.items.first { $0.insertion == #"\frac{}{}"# })
        XCTAssertEqual(result.kind, .command)
        XCTAssertEqual(item.stops, [6, 8, 9])
        XCTAssertEqual(apply(item, result: result, to: #"\fra|"#), #"\frac{}{}"#)
        let heading = try request(#"\subsec|"#)
        XCTAssertEqual(heading.items.first?.insertion, #"\subsection{}"#)
        XCTAssertEqual(heading.items.first?.stops, [12, 13])
    }
    func testCommandCompletesWholeTokenAndRetainsExistingArguments() throws {
        let marked = "😀 \\sec|tion{Existing title}"
        let result = try request(marked)
        let item = try XCTUnwrap(result.items.first { $0.insertion == #"\section"# })
        XCTAssertTrue(item.stops.isEmpty)
        XCTAssertEqual(apply(item, result: result, to: marked), "😀 \\section{Existing title}")
    }
    func testReferenceVariantsMatchLabelsAndHeadingContext() throws {
        for command in ["ref", "eqref", "autoref", "pageref", "nameref", "cref", "Cref", "vref", "cpageref", "labelcref"] {
            let result = try request("\\\(command){topology|}")
            XCTAssertEqual(result.kind, .label)
            XCTAssertEqual(result.items.map(\.insertion), ["sec:intro"])
            XCTAssertTrue(result.items[0].detail.contains("Introduction to topology"))
            XCTAssertTrue(result.items[0].detail.contains("chapters/intro.tex"))
        }
        XCTAssertEqual(try request(#"\hyperref[results|]{read more}"#).items.first?.insertion, "sec:results")
    }
    func testCitationSubstringAndMetadataSearch() throws {
        for query in ["nuth", "TeXbook", "Donald 1984", "1984"] {
            let result = try request("\\cite{\(query)|}")
            XCTAssertEqual(result.items.map(\.insertion), ["knuth1984"])
        }
        XCTAssertEqual(try request(#"\parencite{surfaces|}"#).items.first?.insertion, "doe2025")
    }
    func testCitationOptionsCommaListAndMiddleOfKeyReplacement() throws {
        let marked = "Before \\citep*[see][p.~3]{doe2025, knu|th1984} after"
        let result = try request(marked)
        XCTAssertEqual(result.items.map(\.insertion), ["knuth1984"])
        XCTAssertEqual(apply(result.items[0], result: result, to: marked), "Before \\citep*[see][p.~3]{doe2025, knuth1984} after")
        XCTAssertEqual(try request(#"\cite{doe2025, |}"#).items.map(\.insertion), ["knuth1984"])
        XCTAssertEqual(try request(#"\cref{sec:intro, |}"#).items.map(\.insertion), ["sec:results"])
    }
    func testMultilineCommentAndUTF16ReferenceRange() throws {
        let marked = "😀 \\cite % explanation\r\n [see]\r\n { knu|}"
        let result = try request(marked)
        XCTAssertEqual(apply(result.items[0], result: result, to: marked), "😀 \\cite % explanation\r\n [see]\r\n { knuth1984}")
    }
    func testNoSuggestionsInProseCommentsDefinitionsOrLiteralText() {
        for marked in ["normal prose", "% \\sec", "\\label{sec:", "\\cite[see ", "\\verb|\\sec", "\\begin{verbatim}\n\\sec", "\\begin{minted}{tex}\n\\cite{", "\\\\sec"] {
            XCTAssertNil(LaTeXCompletion.suggestions(in: marked, at: (marked as NSString).length, file: "main.tex", project: project), marked)
        }
    }
    func testEscapedPercentAndEndedLiteralAllowCompletion() throws {
        XCTAssertNotNil(try request(#"\% \sec|"#))
        XCTAssertNotNil(try request("\\begin{verbatim}\n\\fake\n\\end{verbatim}\n\\sec|"))
        XCTAssertNotNil(try request("% comment\r\n\\sec|"))
    }
    func testLiveBuffersReplaceStaleProjectKeys() throws {
        let live = ["chapters/intro.tex": "\\section{Methods}\n\\label{sec:methods}", "references.bib": "@book{newKey, title={New bibliography}}"]
        XCTAssertEqual(try request(#"\ref{|}"#, live: live).items.map(\.insertion), ["sec:methods"])
        XCTAssertEqual(try request(#"\cite{|}"#, live: live).items.map(\.insertion), ["newKey"])
    }
    func testCurrentUnsavedLabelsAndHeadingsNeedNoCompile() throws {
        let result = try request("\\section{Unsaved findings}\n\\label{sec:fresh}\n\\ref{findings|}")
        XCTAssertEqual(result.items.map(\.insertion), ["sec:fresh"])
        let heading = try request(#"\section{Introdu|}"#)
        XCTAssertEqual(heading.kind, .heading)
        XCTAssertEqual(heading.items.first?.insertion, "Introduction to topology")
        XCTAssertEqual(try request(#"\section[Short]{Res|}"#).items.first?.insertion, "Results")
    }
    func testCustomCommandsIncludeRequiredArgumentsAndIgnoreComments() throws {
        let live = ["macros.sty": "\\newcommand{\\vect}[1]{\\mathbf{#1}}\n\\newcommand{\\pair}[2][x]{#1,#2}\n% \\newcommand{\\fake}[1]{}\n\\begin{verbatim}\n\\newcommand{\\fakeTwo}[1]{}\n\\end{verbatim}"]
        XCTAssertEqual(try request(#"\vec|"#, live: live).items.first?.insertion, #"\vec{}"#)
        XCTAssertTrue(try request(#"\vect|"#, live: live).items.contains { $0.insertion == #"\vect{}"# && $0.detail.contains("macros.sty") })
        XCTAssertEqual(try request(#"\pair|"#, live: live).items.first?.insertion, #"\pair{}"#)
        XCTAssertNil(LaTeXCompletion.suggestions(in: #"\fake"#, at: 5, file: "main.tex", project: project, liveBuffers: live))
    }
    func testEnvironmentAndFileCompletionArePreserved() throws {
        XCTAssertEqual(try request(#"\begin{equa|}"#).items.map(\.title), ["equation", "equation*"])
        let files = ["chapters/intro.tex", "figures/chart.pdf", "refs.bib", "notes.txt"]
        XCTAssertEqual(try request(#"\includegraphics[width=\linewidth]{chart|}"#, files: files).items.first?.insertion, "figures/chart.pdf")
        XCTAssertEqual(try request(#"\include{intro|}"#, files: files).items.first?.insertion, "chapters/intro")
        XCTAssertEqual(try request(#"\bibliography{ref|}"#, files: files).items.first?.insertion, "refs")
    }
    func testDuplicateKeysAreStableAndLocalDefinitionWins() throws {
        let result = try request("\\section{Local introduction}\n\\label{sec:intro}\n\\ref{|}")
        XCTAssertEqual(result.items.filter { $0.insertion == "sec:intro" }.count, 1)
        XCTAssertTrue(try XCTUnwrap(result.items.first { $0.insertion == "sec:intro" }).detail.contains("Local introduction"))
    }
    func testCustomDefinitionOverridesBuiltinArgumentCount() throws {
        let result = try request("\\renewcommand{\\frac}[1]{#1}\n\\frac|")
        XCTAssertEqual(result.items.map(\.insertion), [#"\frac{}"#])
        XCTAssertEqual(result.items[0].stops, [6, 7])
    }
    func testInvalidOffsetsAndEmptySourceAreSafe() {
        for offset in [-1, 0, 1, NSNotFound] {
            XCTAssertNil(LaTeXCompletion.suggestions(in: "", at: offset, file: "main.tex", project: project))
        }
    }
}
