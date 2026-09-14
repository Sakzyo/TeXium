import SwiftUI
import AppKit
import TeXiumCore

struct ProjectInspector: View {
    @Bindable var session: ProjectSession
    private let tabs = ["Outline", "Problems", "Build Log", "References", "History", "Git", "Notes", "Statistics"]
    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $session.inspectorTab) { ForEach(tabs, id: \.self) { Text($0).tag($0) } }.labelsHidden().accessibilityIdentifier("project-inspector-picker").padding(.horizontal, 12).frame(height: 37)
            Divider()
            switch session.inspectorTab {
            case "Outline": OutlineInspector(session: session)
            case "Problems": ProblemsInspector(session: session)
            case "Build Log":
                VStack(spacing: 0) {
                    NativeTextDisplay(text: session.buildLog.isEmpty ? "Compile the project to see the complete TeX log." : session.buildLog)
                    Divider(); HStack { Button("Save Log…") { session.saveBuildLog() }; Spacer(); Text("⌘F to find").foregroundStyle(.secondary) }.font(.caption).padding(10)
                }
            case "References": ReferencesInspector(session: session)
            case "History": HistoryInspector(session: session)
            case "Git": GitInspector(session: session)
            case "Notes": NotesInspector(session: session)
            default:
                VStack(alignment: .leading) {
                    Button("Count Document Words") { session.countWords() }.padding(12)
                    NativeTextDisplay(text: session.wordReport.isEmpty ? "Uses texcount to distinguish prose, headings, captions, and mathematics across the main document’s included files." : session.wordReport)
                }
            }
        }
    }
}

struct InspectorEmptyState: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct OutlineInspector: View {
    let session: ProjectSession
    var body: some View {
        if session.outline.isEmpty { InspectorEmptyState(title: "No Sections Yet", symbol: "list.bullet.indent", message: "Add sections or chapters to navigate your document here.") }
        else {
            List {
                ForEach(Array(Set(session.outline.map(\.file))).sorted(), id: \.self) { file in
                    Section((file as NSString).lastPathComponent) {
                        ForEach(session.outline.filter { $0.file == file }) { item in
                            Button { Task { await session.select(item.file, line: item.line) } } label: {
                                HStack { Text(item.title).lineLimit(2); Spacer(); Text("\(item.line)").font(.caption).foregroundStyle(.tertiary) }.padding(.leading, CGFloat(max(0, item.level - 2) * 10))
                            }.buttonStyle(.plain).help("\(file):\(item.line)")
                        }
                    }
                }
            }.listStyle(.inset)
        }
    }
}
struct ProblemsInspector: View {
    let session: ProjectSession
    @State private var filter = "All"
    private var diagnostics: [Diagnostic] { session.diagnostics.filter { filter == "All" || (filter == "Errors" ? $0.severity == .error : $0.severity != .error) } }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Severity", selection: $filter) { Text("All").tag("All"); Text("Errors").tag("Errors"); Text("Warnings").tag("Warnings") }.pickerStyle(.segmented).padding(10)
            if diagnostics.isEmpty { InspectorEmptyState(title: "No Compilation Issues", symbol: "checkmark.circle", message: session.building ? "Typesetting is in progress." : "Diagnostics from your local compiler appear here.") }
            else {
                List {
                    ForEach(Array(Set(diagnostics.map { $0.file ?? "Build" })).sorted(), id: \.self) { file in
                        Section(file) {
                            ForEach(diagnostics.filter { ($0.file ?? "Build") == file }) { diagnostic in
                                Button { session.navigate(diagnostic) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: diagnostic.severity.symbol).foregroundStyle(diagnostic.severity == .error ? Color.red : Color.orange)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(diagnostic.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                                            Text(diagnostic.severity.rawValue.capitalized + (diagnostic.line.map { " · Line \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }.buttonStyle(.plain)
                                .contextMenu {
                                    Button("Copy Diagnostic") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(diagnostic.message, forType: .string) }
                                    Button("Show Build Log") { session.inspectorTab = "Build Log" }
                                }
                            }
                        }
                    }
                }.listStyle(.inset)
            }
        }
    }
}
struct ReferencesInspector: View {
    @Bindable var session: ProjectSession
    @State private var query = ""
    @State private var selected: String?
    var body: some View {
        VStack(spacing: 0) {
            TextField("Search references", text: $query).textFieldStyle(.roundedBorder).padding(10)
            if session.references.isEmpty { InspectorEmptyState(title: "No References", symbol: "books.vertical", message: "Import a .bib file or paste BibTeX entries to get started.") }
            else {
                List(selection: $selected) {
                    ForEach(session.references.filter { query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query) }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")).font(.callout).lineLimit(3)
                            Text([entry.author, entry.year].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(entry.key).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 3).tag(entry.id)
                        .onTapGesture(count: 2) { session.insert("\\cite{\(entry.key)}") }
                        .contextMenu {
                            Button("Insert Citation") { session.insert("\\cite{\(entry.key)}") }
                            Button("Edit BibTeX Source") { Task { await session.select(entry.file, line: entry.line) } }
                            Button("Copy Citation Key") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.key, forType: .string) }
                        }
                    }
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Menu { Button("Import .bib File…") { session.importFiles() }; Button("Paste BibTeX…") { session.sheet = .pasteBib } } label: { Label("Add", systemImage: "plus") }
                Spacer()
                Button("Insert Citation") { if let entry = session.references.first(where: { $0.id == selected }) { session.insert("\\cite{\(entry.key)}") } }.disabled(selected == nil || session.currentBuffer == nil)
            }.padding(10).font(.caption)
        }
    }
}
struct NotesInspector: View {
    @Bindable var session: ProjectSession
    @State private var showResolved = false
    private var visibleNotes: [UserNote] { session.notes.filter { showResolved || !$0.resolved } }
    var body: some View {
        VStack(spacing: 0) {
            Toggle("Show resolved notes", isOn: $showResolved).font(.caption).padding(10)
            if visibleNotes.isEmpty {
                InspectorEmptyState(title: "No Personal Notes", symbol: "note.text", message: "Add a note about this project to see it here.")
            } else {
                List {
                    ForEach(visibleNotes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.text).textSelection(.enabled).strikethrough(note.resolved)
                            if let file = note.file { Button("\(file):\(note.line ?? 1)") { Task { await session.select(file, line: note.line) } }.font(.caption).buttonStyle(.link) }
                            HStack {
                                Text(note.created, style: .date).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(note.resolved ? "Reopen" : "Resolve") {
                                    if let index = session.notes.firstIndex(where: { $0.id == note.id }) { session.notes[index].resolved.toggle(); session.persistPreferences() }
                                }.font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                }.listStyle(.inset)
            }
            Button("Add Personal Note…", systemImage: "note.text.badge.plus") { session.sheet = .note }.padding(10)
        }
    }
}
