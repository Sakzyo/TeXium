import Foundation

public enum ProjectTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank = "Blank", article = "Article", report = "Report", book = "Book", letter = "Letter", beamer = "Presentation", cv = "Curriculum Vitae", thesis = "Thesis", homework = "Homework", poster = "Poster"
    public var id: String { rawValue }
    public var symbol: String {
        switch self { case .blank: "doc"; case .article: "doc.text"; case .report: "chart.bar.doc.horizontal"; case .book: "book.closed"; case .letter: "envelope"; case .beamer: "rectangle.on.rectangle"; case .cv: "person.text.rectangle"; case .thesis: "graduationcap"; case .homework: "pencil.and.outline"; case .poster: "rectangle.portrait" }
    }
    public var detail: String {
        switch self { case .blank: "A minimal document, ready for your ideas."; case .article: "An abstract, sections, and a bibliography."; case .report: "A structured report with chapters."; case .book: "Front matter, chapters, and a contents page."; case .letter: "A formal letter in a classic layout."; case .beamer: "Slides, equations, and presentation structure."; case .cv: "A clean, editable academic CV."; case .thesis: "Chapters, references, and a title page."; case .homework: "Numbered exercises with room for solutions."; case .poster: "A landscape research poster using standard LaTeX." }
    }
    public var source: String {
        if self == .letter { return "\\documentclass{letter}\n\\signature{Your name}\n\\address{Your address}\n\\begin{document}\n\\begin{letter}{Recipient\\\\Address}\n\\opening{Dear Colleague,}\nYour letter begins here.\n\\closing{Sincerely,}\n\\end{letter}\n\\end{document}\n" }
        if self == .beamer { return "\\documentclass{beamer}\n\\usepackage{amsmath}\n\\title{A New Perspective}\n\\author{Your name}\n\\date{\\today}\n\\begin{document}\n\\frame{\\titlepage}\n\\begin{frame}{An idea worth sharing}\n\\begin{itemize}\n  \\item Start with the question.\n  \\item Show what you discovered.\n\\end{itemize}\n\\end{frame}\n\\end{document}\n" }
        let documentClass = self == .book ? "book" : (self == .report || self == .thesis ? "report" : "article")
        let title = self == .cv ? "Your Name" : self == .homework ? "Problem Set" : self == .thesis ? "Thesis Title" : "A New Perspective"
        var body = "\\section{Introduction}\nStart writing here. Your files stay on your Mac.\n"
        if self == .blank { body = "Start writing here.\n" }
        if [.book, .report, .thesis].contains(self) { body = "\\tableofcontents\n\\chapter{Introduction}\nStart writing here.\n" }
        if self == .cv { body = "\\section*{Education}\nDegree, Institution, Year\n\\section*{Experience}\nRole, Organization\n\\section*{Publications}\nYour publications.\n" }
        if self == .homework { body = "\\section*{Exercise 1}\nState the problem.\n\\paragraph{Solution}\nExplain your reasoning.\n" }
        if self == .article { body = "\\begin{abstract}\nA concise account of your work.\n\\end{abstract}\n" + body + "\n\\section{Approach}\nBuild on earlier work~\\cite{knuth1984}.\n\n\\begin{equation}\n  e^{i\\pi} + 1 = 0\n  \\label{eq:euler}\n\\end{equation}\n\n\\bibliographystyle{plain}\n\\bibliography{references}\n" }
        let geometry = self == .poster ? "\\usepackage[a3paper,landscape,margin=2cm]{geometry}" : "\\usepackage[margin=1in]{geometry}"
        return "\\documentclass[11pt]{\(documentClass)}\n\\usepackage[T1]{fontenc}\n\\usepackage{amsmath,amssymb,graphicx}\n\(geometry)\n\\usepackage{hyperref}\n\\title{\(title)}\n\\author{Your name}\n\\date{\\today}\n\n\\begin{document}\n\\maketitle\n\n\(body)\n\\end{document}\n"
    }
}
public enum TemplateService {
    public static let bibliography = "@book{knuth1984,\n  author = {Donald E. Knuth},\n  title = {The TeXbook},\n  publisher = {Addison-Wesley},\n  year = {1984}\n}\n"
    public static func create(_ template: ProjectTemplate, at root: URL) throws {
        guard !FileManager.default.fileExists(atPath: root.path) else { throw TeXiumError.message("A folder already exists at that location. Choose a new project name.") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try template.source.write(to: root.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
            if template == .article { try bibliography.write(to: root.appendingPathComponent("references.bib"), atomically: true, encoding: .utf8) }
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }
}
