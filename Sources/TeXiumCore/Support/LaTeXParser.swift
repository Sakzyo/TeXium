import Foundation

public enum LaTeXParser {
    public static func matchingEnvironment(at offset: Int, in source: String) -> NSRange? {
        let clean = uncomment(source) as NSString
        let expression = try! NSRegularExpression(pattern: #"\\(begin|end)\s*\{([^}]+)\}"#)
        let tokens = expression.matches(in: clean as String, range: NSRange(location: 0, length: clean.length))
        var stack: [NSTextCheckingResult] = []
        var containing: (Int, NSRange)?
        for token in tokens {
            if clean.substring(with: token.range(at: 1)) == "begin" { stack.append(token); continue }
            guard let open = stack.last, clean.substring(with: open.range(at: 2)) == clean.substring(with: token.range(at: 2)) else { continue }
            stack.removeLast()
            if NSLocationInRange(offset, token.range) { return open.range }
            if NSLocationInRange(offset, open.range) { return token.range }
            if offset > open.range.location && offset < token.range.location, open.range.location >= (containing?.0 ?? -1) { containing = (open.range.location, token.range) }
        }
        return containing?.1
    }
    // Replace comments with spaces to retain UTF-16 source offsets for navigation.
    public static func uncomment(_ source: String) -> String {
        let chars = Array(source.utf16)
        var result = chars; var comment = false; var escapes = 0
        for i in chars.indices {
            let c = chars[i]
            if c == 10 || c == 13 { comment = false }
            if c == 37 && escapes % 2 == 0 { comment = true }
            if comment { result[i] = 32 }
            escapes = c == 92 ? escapes + 1 : 0
        }
        return String(decoding: result, as: UTF16.self)
    }
    public static func outline(_ source: String, file: String) -> [OutlineItem] {
        let clean = uncomment(source) as NSString
        let regex = try! NSRegularExpression(pattern: #"\\(part|chapter|section|subsection|subsubsection|paragraph)\*?\s*(?:\[[^\]]*\])?\s*\{"#)
        let levels = ["part", "chapter", "section", "subsection", "subsubsection", "paragraph"]
        return regex.matches(in: clean as String, range: NSRange(location: 0, length: clean.length)).compactMap { match in
            let start = NSMaxRange(match.range); var i = start; var depth = 1; var escaped = false
            while i < clean.length && depth > 0 {
                let c = clean.character(at: i)
                if !escaped { if c == 123 { depth += 1 }; if c == 125 { depth -= 1 } }
                escaped = c == 92 && !escaped
                i += 1
            }
            guard depth == 0 else { return nil }
            return OutlineItem(title: clean.substring(with: NSRange(location: start, length: i - start - 1)), level: levels.firstIndex(of: clean.substring(with: match.range(at: 1))) ?? 2, file: file, line: lineNumber(at: match.range.location, in: source), offset: match.range.location)
        }
    }
    public static func keys(_ source: String, command: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: command)
        let regex = try! NSRegularExpression(pattern: "\\\\" + escaped + #"\*?\s*(?:\[[^\]]*\]\s*)*\{([^}]+)\}"#)
        let clean = uncomment(source) as NSString
        return regex.matches(in: clean as String, range: NSRange(location: 0, length: clean.length)).flatMap {
            clean.substring(with: $0.range(at: 1)).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
    public static func lineNumber(at offset: Int, in text: String) -> Int {
        let ns = text as NSString
        let prefix = ns.substring(to: min(max(0, offset), ns.length))
        return prefix.reduce(1) { $1 == "\n" || $1 == "\r\n" ? $0 + 1 : $0 }
    }
    public static func offset(ofLine line: Int, in text: String) -> Int {
        guard line > 1 else { return 0 }
        let ns = text as NSString; var offset = 0; var current = 1
        while offset < ns.length && current < line { offset = NSMaxRange(ns.lineRange(for: NSRange(location: offset, length: 0))); current += 1 }
        return min(offset, ns.length)
    }
}
