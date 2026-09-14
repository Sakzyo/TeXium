import AppKit
import XCTest
@testable import TeXiumCore

final class SyntaxHighlightingTests: XCTestCase {
    func testHexInputValidationAndRoundTrip() throws {
        let color = try XCTUnwrap(SyntaxPalette.color(fromHex: " #fF8800 "))
        XCTAssertEqual(SyntaxPalette.hex(for: color), "#FF8800")
        XCTAssertEqual(SyntaxPalette.color(fromHex: "FF8800"), color)
        for invalid in ["", "#", "#12345", "#1234567", "#GG0000", "0000-1", "0000+1"] {
            XCTAssertNil(SyntaxPalette.color(fromHex: invalid))
        }
    }

    func testPalettePersistenceAndIndividualReset() throws {
        let suite = "TeXium-Syntax-Test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var palette = SyntaxPalette()
        palette.setColor(NSColor(srgbRed: 0.8, green: 0.2, blue: 0.4, alpha: 1), for: .commands)
        palette.setColor(NSColor(srgbRed: 0.2, green: 0.7, blue: 0.3, alpha: 1), for: .comments)
        defaults.set(palette.data, forKey: SyntaxPalette.defaultsKey)
        var restored = SyntaxPalette(data: try XCTUnwrap(defaults.data(forKey: SyntaxPalette.defaultsKey)))
        XCTAssertEqual(restored, palette)
        assertColor(restored.color(for: .commands), matches: palette.color(for: .commands))
        restored.reset(.commands)
        XCTAssertFalse(restored.isCustomized(.commands))
        XCTAssertEqual(restored.color(for: .commands), SyntaxCategory.commands.defaultColor)
        assertColor(restored.color(for: .comments), matches: palette.color(for: .comments))
        XCTAssertFalse(SyntaxPalette().hasCustomColors)
    }

    func testInvalidPreferencesKeepOtherValidColors() {
        let data = Data(#"{"commands":{"red":0.2,"green":0.3,"blue":0.4},"comments":{"red":9,"green":0,"blue":0},"brackets":"bad","unknown":{"red":1,"green":0,"blue":0}}"#.utf8)
        let palette = SyntaxPalette(data: data)
        XCTAssertTrue(palette.isCustomized(.commands))
        XCTAssertFalse(palette.isCustomized(.comments))
        XCTAssertFalse(palette.isCustomized(.brackets))
        XCTAssertEqual(palette.color(for: .comments), SyntaxCategory.comments.defaultColor)
        XCTAssertEqual(SyntaxPalette(data: Data("invalid".utf8)), SyntaxPalette())
    }

    func testAllSyntaxColorsAndCommentPrecedenceWithUnicode() {
        let source = "😀 \\textbf{Bold} $x$ \\cite{knuth}\n\\section{Intro}\n@article{key,\n% \\section{Ignored} @article{ignored,\n"
        let storage = NSTextStorage(string: source)
        var palette = SyntaxPalette()
        for (index, category) in SyntaxCategory.allCases.enumerated() {
            palette.setColor(NSColor(srgbRed: Double(index + 1) / 8, green: 0.1, blue: 0.7, alpha: 1), for: category)
        }
        LaTeXSyntaxHighlighter.apply(to: storage, range: NSRange(location: 0, length: storage.length), palette: palette)
        let probes: [(String, SyntaxCategory)] = [
            (#"\textbf"#, .commands), ("{Bold}", .brackets), ("$x$", .math),
            (#"\cite{knuth}"#, .references), (#"\section{Intro}"#, .headings),
            ("@article{key", .bibliography), ("%", .comments), ("@article{ignored", .comments)
        ]
        for (token, category) in probes {
            let index = (source as NSString).range(of: token).location
            assertColor(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor, matches: palette.color(for: category))
        }
        XCTAssertEqual(storage.string, source)
    }

    func testRecolorAndDisablePreserveTextAndOtherAttributes() {
        let source = "\\textbf{First}\n% Second line"
        let storage = NSTextStorage(string: source)
        let full = NSRange(location: 0, length: storage.length)
        let marker = NSAttributedString.Key("test-preserved-attribute")
        storage.addAttribute(marker, value: "preserved", range: full)
        var palette = SyntaxPalette()
        palette.setColor(.red, for: .commands)
        LaTeXSyntaxHighlighter.apply(to: storage, range: full, palette: palette)
        let commentOffset = (source as NSString).range(of: "%").location
        let originalCommentColor = storage.attribute(.foregroundColor, at: commentOffset, effectiveRange: nil) as? NSColor
        palette.setColor(.green, for: .commands)
        LaTeXSyntaxHighlighter.apply(to: storage, range: (source as NSString).lineRange(for: NSRange(location: 0, length: 0)), palette: palette)
        assertColor(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, matches: palette.color(for: .commands))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: commentOffset, effectiveRange: nil) as? NSColor, originalCommentColor)
        LaTeXSyntaxHighlighter.apply(to: storage, range: full, palette: palette, enabled: false)
        storage.enumerateAttribute(.foregroundColor, in: full) { color, _, _ in XCTAssertEqual(color as? NSColor, .textColor) }
        XCTAssertEqual(storage.string, source)
        XCTAssertEqual(storage.attribute(marker, at: 0, effectiveRange: nil) as? String, "preserved")
    }

    private func assertColor(_ color: NSColor?, matches expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual = color?.usingColorSpace(.sRGB), let expected = expected.usingColorSpace(.sRGB) else {
            XCTFail("Expected an RGB syntax color", file: file, line: line); return
        }
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001, file: file, line: line)
    }
}
