import XCTest

final class TeXiumUITests: XCTestCase {
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
        editor.typeKey(.end, modifierFlags: [.command])
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
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'matches in'")).firstMatch.waitForExistence(timeout: 10))
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
