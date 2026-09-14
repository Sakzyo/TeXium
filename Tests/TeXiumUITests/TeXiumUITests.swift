import XCTest

final class TeXiumUITests: XCTestCase {
    @MainActor func testEnvironmentTemplateWorkflow() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-Templates-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\\documentclass{article}\n".write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = XCUIApplication()
        app.launchArguments = ["--project", root.path, "-ApplePersistenceIgnoreState", "YES", "-completion", "YES", "-autoClose", "YES", "-useSpaces", "YES", "-tabWidth", "4"]
        app.launch(); defer { app.terminate() }
        let editor = app.textViews["source-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click(); editor.typeKey(.downArrow, modifierFlags: [.command]); editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeText("\\beg")
        XCTAssertTrue(app.staticTexts["completion-\\begin{}"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: []); editor.typeText("fig")
        XCTAssertTrue(app.staticTexts["completion-figure"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: [])
        editor.typeText("chart.pdf"); editor.typeKey(.tab, modifierFlags: [])
        editor.typeText("First caption"); editor.typeKey(.tab, modifierFlags: [])
        editor.typeKey(.tab, modifierFlags: [.shift]); editor.typeText("Figure caption")
        editor.typeKey(.tab, modifierFlags: []); editor.typeText("fig:chart"); editor.typeKey(.tab, modifierFlags: [])
        let figure = "\\begin{figure}\n    \\centering\n    \\includegraphics[width=0.5\\linewidth]{chart.pdf}\n    \\caption{Figure caption}\n    \\label{fig:chart}\n\\end{figure}"
        XCTAssertTrue((editor.value as? String)?.hasSuffix(figure) == true, editor.value as? String ?? "")

        editor.typeText("\n\\begin{enum")
        XCTAssertTrue(app.staticTexts["completion-enumerate"].waitForExistence(timeout: 5))
        let before = editor.value as? String
        editor.typeKey(.return, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\begin{enumerate}\n    \\item \n\\end{enumerate}") == true)
        editor.typeKey("z", modifierFlags: [.command])
        XCTAssertEqual(editor.value as? String, before, "One undo must restore the entire environment completion")
        editor.typeKey(.rightArrow, modifierFlags: []) // Undo selects the restored token; collapse it before requesting suggestions.
        editor.typeKey(.escape, modifierFlags: [.control])
        XCTAssertTrue(app.staticTexts["completion-enumerate"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: []); editor.typeText("Numbered item"); editor.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\begin{enumerate}\n    \\item Numbered item\n\\end{enumerate}") == true)

        editor.typeText("\n\\begin{itemize}")
        XCTAssertTrue(app.staticTexts["completion-itemize"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: []); editor.typeText("Bullet item"); editor.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\begin{itemize}\n    \\item Bullet item\n\\end{itemize}") == true)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Complete figure and list templates"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testTemplateWithoutAutomaticBraceClosure() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-Template-No-Braces-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\\documentclass{article}\n".write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = XCUIApplication()
        app.launchArguments = ["--project", root.path, "-ApplePersistenceIgnoreState", "YES", "-completion", "YES", "-autoClose", "NO", "-useSpaces", "YES", "-tabWidth", "2"]
        app.launch(); defer { app.terminate() }
        let editor = app.textViews["source-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click(); editor.typeKey(.downArrow, modifierFlags: [.command]); editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeText("  \\begin{item")
        XCTAssertTrue(app.staticTexts["completion-itemize"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: []); editor.typeText("Nested item"); editor.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("  \\begin{itemize}\n    \\item Nested item\n  \\end{itemize}") == true)
    }

    @MainActor func testContextCompletionWorkflow() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-Completion-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\\documentclass{article}\n".write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        try "\\section{Introduction to topology}\n\\label{sec:intro}\n".write(to: root.appendingPathComponent("chapter.tex"), atomically: true, encoding: .utf8)
        try "@book{knuth1984, title={The TeXbook}, author={Donald Knuth}, year={1984}}\n".write(to: root.appendingPathComponent("refs.bib"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = XCUIApplication()
        app.launchArguments = ["--project", root.path, "-ApplePersistenceIgnoreState", "YES", "-completion", "YES", "-autoClose", "YES"]
        app.launch(); defer { app.terminate() }
        let editor = app.textViews["source-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click(); editor.typeKey(.downArrow, modifierFlags: [.command]); editor.typeKey(.rightArrow, modifierFlags: [])
        let choices = app.tables["latex-completions"]
        editor.typeText("\n")
        editor.typeText("\\sec")
        XCTAssertTrue(choices.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["completion-\\section{}"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: [])
        editor.typeText("Fresh heading"); editor.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\section{Fresh heading}") == true)

        editor.typeText("\n\\ref")
        XCTAssertTrue(app.staticTexts["completion-\\ref{}"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: [])
        editor.typeText("topology")
        XCTAssertTrue(app.staticTexts["completion-sec:intro"].waitForExistence(timeout: 5))
        editor.typeKey(.return, modifierFlags: []); editor.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\ref{sec:intro}") == true)

        editor.typeText("\n\\cite")
        XCTAssertTrue(app.staticTexts["completion-\\cite{}"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: [])
        editor.typeText("TeXbook")
        XCTAssertTrue(app.staticTexts["completion-knuth1984"].waitForExistence(timeout: 5))
        editor.typeKey(.return, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\cite{knuth1984}") == true)
        editor.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\cite{TeXbook}") == true, "Accepting completion must undo as one edit")

        editor.typeKey(.downArrow, modifierFlags: [.command]); editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeText("\n\\fra")
        XCTAssertTrue(app.staticTexts["completion-\\frac{}{}"].waitForExistence(timeout: 5))
        editor.typeKey(.tab, modifierFlags: [])
        editor.typeText("a"); editor.typeKey(.tab, modifierFlags: []); editor.typeText("b"); editor.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\frac{a}{b}") == true)

        editor.typeText("\n\\sec")
        XCTAssertTrue(choices.waitForExistence(timeout: 5))
        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(choices.exists)
        XCTAssertTrue((editor.value as? String)?.hasSuffix("\\sec") == true)
        editor.typeKey("s", modifierFlags: [.command])
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Context completion workflow"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testCompiledWorkspaceRestoresAfterRelaunch() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-Restore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\\documentclass{article}\n\\begin{document}\n\\section{Restored workspace}\nStartup verification.\n\\end{document}\n".write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = XCUIApplication()
        app.launchArguments = ["--project", root.path, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.textViews["source-editor"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Compile"].firstMatch.click()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Typeset in' OR value BEGINSWITH 'Typeset in'"), evaluatedWith: app.staticTexts["build-status"].firstMatch)
        waitForExpectations(timeout: 45)

        // Exercise real AppKit termination and restoration, including a saved
        // PDF and changing from a compact source window back to four panes.
        for compact in [false, true] {
            if compact {
                app.radioButtons["chevron.left.forwardslash.chevron.right"].click()
                app.buttons["Toggle Inspector"].click()
                app.typeKey("s", modifierFlags: [.command, .control])
                let window = app.windows.firstMatch
                window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
                    .press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.8)))
            }
            app.typeKey("q", modifierFlags: [.command])
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
            app.launchArguments = ["-ApplePersistenceIgnoreState", "NO"]
            app.launch()
            XCTAssertTrue(app.textViews["source-editor"].firstMatch.waitForExistence(timeout: 15))
            XCTAssertTrue((app.textViews["source-editor"].firstMatch.value as? String)?.contains("Startup verification") == true)
            app.radioButtons["rectangle.split.2x1"].click()
            if app.buttons["Show Sidebar"].exists { app.buttons["Show Sidebar"].click() }
            if !app.descendants(matching: .any)["project-inspector-picker"].exists { app.buttons["Toggle Inspector"].click() }
            XCTAssertTrue(app.textFields["Find in PDF"].firstMatch.waitForExistence(timeout: 10))
            // Startup previously crashed after the one-second launch probe.
            // Keep interacting after the PDF and inspector have been laid out.
            for _ in 0..<3 {
                app.buttons["Toggle Inspector"].click()
                app.buttons["Toggle Inspector"].click()
                assertWorkspaceFits(app, compiled: true)
            }
        }
    }

    @MainActor func testUncompiledWorkspaceWithBothSidebars() throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-Layout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\\documentclass{article}\n\\begin{document}\nLayout verification.\n\\end{document}\n".write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = XCUIApplication()
        app.launchArguments = ["--project", root.path, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.textViews["source-editor"].firstMatch.waitForExistence(timeout: 15))
        app.radioButtons["rectangle.split.2x1"].click()
        if app.buttons["Show Sidebar"].exists { app.buttons["Show Sidebar"].click() }
        if !app.descendants(matching: .any)["project-inspector-picker"].exists { app.buttons["Toggle Inspector"].click() }
        XCTAssertTrue(app.buttons["Compile Project"].firstMatch.waitForExistence(timeout: 5))
        assertWorkspaceFits(app)
        // Exercise both collapse orders; every return to four visible panes
        // must preserve the document height and keep the sidebars on screen.
        for _ in 0..<2 {
            app.typeKey("s", modifierFlags: [.command, .control])
            app.buttons["Toggle Inspector"].click()
            app.typeKey("s", modifierFlags: [.command, .control])
            app.buttons["Toggle Inspector"].click()
            assertWorkspaceFits(app)
        }
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
            .press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.8)))
        assertWorkspaceFits(app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".texium-build/preview/main.pdf").path))
    }

    @MainActor private func assertWorkspaceFits(_ app: XCUIApplication, compiled: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        let viewport = app.scrollViews.containing(.textView, identifier: "source-editor").firstMatch
        let inspector = app.descendants(matching: .any)["project-inspector-picker"].firstMatch
        let sidebar = app.descendants(matching: .any)["project-navigator"].firstMatch
        let preview = app.descendants(matching: .any)["pdf-pane"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(preview.waitForExistence(timeout: 5), file: file, line: line)
        let bounds = window.frame.insetBy(dx: -2, dy: -2)
        XCTAssertGreaterThan(viewport.frame.height, window.frame.height * 0.7, file: file, line: line)
        XCTAssertTrue(bounds.contains(viewport.frame), "Source viewport must fit the window", file: file, line: line)
        XCTAssertTrue(bounds.contains(inspector.frame), "Inspector must remain on screen", file: file, line: line)
        XCTAssertTrue(bounds.contains(sidebar.frame), "Navigator must remain on screen", file: file, line: line)
        XCTAssertTrue(bounds.contains(preview.frame), "PDF pane must fit the window", file: file, line: line)
        // AX groups report the union of accessible children, not blank canvas.
        // Check the preview header and centered empty-state action instead.
        XCTAssertLessThan(abs(preview.frame.minY - viewport.frame.minY), 50, file: file, line: line)
        XCTAssertLessThanOrEqual(viewport.frame.maxX, preview.frame.minX + 2, file: file, line: line)
        XCTAssertLessThanOrEqual(preview.frame.maxX, inspector.frame.minX + 2, file: file, line: line)
        if !compiled {
            let emptyAction = app.buttons["Compile Project"].firstMatch.frame
            XCTAssertGreaterThan(emptyAction.midY, viewport.frame.minY + viewport.frame.height * 0.4, file: file, line: line)
            XCTAssertLessThan(emptyAction.midY, viewport.frame.minY + viewport.frame.height * 0.7, file: file, line: line)
            XCTAssertGreaterThan(emptyAction.midX, viewport.frame.maxX, file: file, line: line)
        }
    }

    @MainActor func testLocalAuthoringWorkflow() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Research")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TeXium-UI-" + UUID().uuidString)
        try FileManager.default.copyItem(at: fixture, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = XCUIApplication()
        app.launchArguments = ["--project", root.path, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }

        let editor = app.textViews["source-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        XCTAssertTrue((editor.value as? String)?.contains("A Small Atlas of Ideas") == true)
        let compile = app.buttons["Compile"].firstMatch
        XCTAssertTrue(compile.waitForExistence(timeout: 5))
        compile.click()
        let status = app.staticTexts["build-status"].firstMatch
        let compiled = NSPredicate(format: "label BEGINSWITH 'Typeset in' OR value BEGINSWITH 'Typeset in'")
        expectation(for: compiled, evaluatedWith: status)
        waitForExpectations(timeout: 45)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".texium-build/preview/main.pdf").path))

        editor.click()
        // Command-Down is AppKit's move-to-end-of-document shortcut.
        // Send an unmodified arrow before typing to clear synthesized modifiers.
        editor.typeKey(.downArrow, modifierFlags: [.command])
        editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeText("\n% Native UI verification\n")
        editor.typeKey("s", modifierFlags: [.command])
        let saved = NSPredicate { _, _ in
            (try? String(contentsOf: root.appendingPathComponent("main.tex"))).map { $0.contains("% Native UI verification") } ?? false
        }
        expectation(for: saved, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        editor.typeKey("z", modifierFlags: [.command])

        app.buttons["Search Project"].firstMatch.click()
        let query = app.textFields["Find"].firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.click(); query.typeText("Knuth")
        app.buttons["Find"].firstMatch.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '4 matches in 2 files' OR value CONTAINS '4 matches in 2 files'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.click()

        app.buttons["Toggle Inspector"].firstMatch.click()
        app.buttons["Toggle Inspector"].firstMatch.click()
        app.typeKey(",", modifierFlags: [.command])
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.buttons[XCUIIdentifierCloseWindow].click()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "TeXium native authoring workflow"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
