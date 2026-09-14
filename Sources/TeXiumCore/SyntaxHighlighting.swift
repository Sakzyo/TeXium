import AppKit

public enum SyntaxCategory: String, CaseIterable, Sendable {
    case commands, brackets, math, references, headings, comments, bibliography

    public var title: String {
        switch self {
        case .commands: return "Commands"
        case .brackets: return "Braces and brackets"
        case .math: return "Math delimiters"
        case .references: return "Labels and citations"
        case .headings: return "Section headings"
        case .comments: return "Comments"
        case .bibliography: return "BibTeX entries"
        }
    }

    public var example: String {
        switch self {
        case .commands: return #"\textbf"#
        case .brackets: return "{ } [ ]"
        case .math: return #"$ … $  \( … \)"#
        case .references: return #"\cite{knuth}  \label{intro}"#
        case .headings: return #"\section{Introduction}"#
        case .comments: return "% A comment"
        case .bibliography: return "@article{knuth,"
        }
    }

    public var defaultColor: NSColor {
        switch self {
        case .commands, .bibliography: return .systemPurple
        case .brackets, .comments: return .secondaryLabelColor
        case .math: return .systemPink
        case .references: return .systemTeal
        case .headings: return .systemBlue
        }
    }
}

/// Only explicit choices are serialized; semantic defaults stay appearance-aware.
public struct SyntaxPalette: Equatable, Sendable {
    public static let defaultsKey = "syntaxColors"
    private var overrides: [String: RGBColor] = [:]

    public init(data: Data = Data()) {
        // Decode each entry separately so a damaged preference does not discard
        // the user's other colors. Unknown categories are ignored.
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for category in SyntaxCategory.allCases {
            guard let entry = entries[category.rawValue] as? [String: Double],
                  let red = entry["red"], let green = entry["green"], let blue = entry["blue"],
                  [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { continue }
            overrides[category.rawValue] = RGBColor(red: red, green: green, blue: blue)
        }
    }

    public var data: Data { (try? JSONEncoder().encode(overrides)) ?? Data() }
    public var hasCustomColors: Bool { !overrides.isEmpty }
    public func isCustomized(_ category: SyntaxCategory) -> Bool { overrides[category.rawValue] != nil }

    public func color(for category: SyntaxCategory) -> NSColor {
        guard let color = overrides[category.rawValue] else { return category.defaultColor }
        return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    public mutating func setColor(_ color: NSColor, for category: SyntaxCategory) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return }
        let bounded = components.map { Double(min(1, max(0, $0))) }
        overrides[category.rawValue] = RGBColor(red: bounded[0], green: bounded[1], blue: bounded[2])
    }

    public mutating func reset(_ category: SyntaxCategory) { overrides.removeValue(forKey: category.rawValue) }

    public static func color(fromHex input: String) -> NSColor? {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                       green: Double((value >> 8) & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }

    public static func hex(for color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    private struct RGBColor: Codable, Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }
}

public enum LaTeXSyntaxHighlighter {
    private static let patterns: [(NSRegularExpression, SyntaxCategory)] = ([
        (#"\\[a-zA-Z@]+\*?"#, .commands),
        (#"[{}\[\]]"#, .brackets),
        (#"\$\$?|\\[\(\)\[\]]"#, .math),
        (#"\\(?:label|(?:auto|eq|page)?ref|[a-zA-Z]*cite[a-zA-Z]*)\*?(?:\[[^\]]*\])*\{[^}]*\}"#, .references),
        (#"\\(?:part|chapter|section|subsection|subsubsection|paragraph)\*?\{[^}]*\}"#, .headings),
        (#"@[a-zA-Z]+\s*\{[^,]*"#, .bibliography),
        (#"(?m)(?<!\\)(?:\\\\)*%[^\r\n]*"#, .comments)
    ] as [(String, SyntaxCategory)]).map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    public static func apply(to storage: NSTextStorage, range input: NSRange, palette: SyntaxPalette, enabled: Bool = true) {
        guard storage.length > 0 else { return }
        let range = NSIntersectionRange(input, NSRange(location: 0, length: storage.length))
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        guard enabled else { return }
        for (pattern, category) in patterns {
            let color = palette.color(for: category)
            for match in pattern.matches(in: storage.string, range: range) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }
}
