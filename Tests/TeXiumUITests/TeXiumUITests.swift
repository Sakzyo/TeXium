import XCTest

final class TeXiumUITests: XCTestCase {
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

    @MainActor private func assertWorkspaceFits(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
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
        let emptyAction = app.buttons["Compile Project"].firstMatch.frame
        XCTAssertGreaterThan(emptyAction.midY, viewport.frame.minY + viewport.frame.height * 0.4, file: file, line: line)
        XCTAssertLessThan(emptyAction.midY, viewport.frame.minY + viewport.frame.height * 0.7, file: file, line: line)
        XCTAssertLessThanOrEqual(viewport.frame.maxX, preview.frame.minX + 2, file: file, line: line)
        XCTAssertLessThanOrEqual(preview.frame.maxX, inspector.frame.minX + 2, file: file, line: line)
        XCTAssertGreaterThan(app.buttons["Compile Project"].firstMatch.frame.midX, viewport.frame.maxX, file: file, line: line)
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
