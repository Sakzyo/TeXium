import Foundation

public enum DiagnosticsParser {
    public static func parse(_ log: String, mainFile: String = "main.tex") -> [Diagnostic] {
        var result: [Diagnostic] = []; var seen = Set<String>()
        let fileLine = try! NSRegularExpression(pattern: #"^(.+\.(?:tex|sty|cls|bib)):(\d+):\s*(.+)$"#)
        let linePattern = try! NSRegularExpression(pattern: #"(?:input line|at lines?|on line)\s+(\d+)"#)
        var pendingError: Int?
        for raw in log.components(separatedBy: .newlines) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            let ns = text as NSString
            var diagnostic: Diagnostic?
            if let match = fileLine.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                diagnostic = Diagnostic(severity: text.contains("Warning") ? .warning : .error, message: ns.substring(with: match.range(at: 3)), file: ns.substring(with: match.range(at: 1)), line: Int(ns.substring(with: match.range(at: 2))))
            } else if text.hasPrefix("!") {
                diagnostic = Diagnostic(severity: .error, message: String(text.dropFirst()).trimmingCharacters(in: .whitespaces), file: mainFile)
            } else if text.hasPrefix("l."), let index = pendingError {
                let number = text.dropFirst(2).prefix(while: { $0.isNumber }); result[index].line = Int(number); pendingError = nil
            } else if text.contains("Warning:") || text.contains("Overfull ") || text.contains("Underfull ") || text.contains("Missing character:") {
                let match = linePattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
                let line = match.flatMap { Int(ns.substring(with: $0.range(at: 1))) }
                let badBox = text.contains("Overfull ") || text.contains("Underfull ")
                diagnostic = Diagnostic(severity: badBox ? .badBox : .warning, message: text, file: mainFile, line: line)
            }
            if let value = diagnostic {
                let key = "\(value.severity):\(value.file ?? ""):\(value.line ?? 0):\(value.message)"
                if seen.insert(key).inserted { result.append(value); if text.hasPrefix("!") { pendingError = result.count - 1 } }
            }
        }
        return result
    }
}
