import SwiftUI
import TeXiumCore

struct ProjectSearchSheet: View {
    @Bindable var session: ProjectSession
    @State private var query = ""
    @State private var replacement = ""
    @State private var regex = false
    @State private var matchCase = false
    @State private var wholeWord = false
    @State private var currentFile = false
    @State private var result: SearchResult?
    @State private var searchedQuery = ""
    @State private var searchedOptions = SearchOptions()
    @State private var busy = false
    @State private var confirmReplace = false
    @State private var error: String?
    private var hits: [SearchHit] { result?.hits.filter { !currentFile || $0.file == session.selected } ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Find in Project").font(.title2.weight(.semibold)); Spacer(); if busy { ProgressView().controlSize(.small) } }.padding(.bottom, 6)
            HStack { TextField("Find", text: $query).onSubmit { search() }; Button("Find") { search() }.disabled(query.isEmpty || busy).keyboardShortcut(.defaultAction) }
            HStack { TextField("Replace with", text: $replacement); Button("Replace All…") { confirmReplace = true }.disabled(hits.isEmpty || query != searchedQuery || busy) }
            HStack(spacing: 18) { Toggle("Regex", isOn: $regex); Toggle("Match case", isOn: $matchCase); Toggle("Whole word", isOn: $wholeWord); Toggle("Current file only", isOn: $currentFile) }.font(.caption)
                .onChange(of: regex) { _, _ in result = nil }.onChange(of: matchCase) { _, _ in result = nil }.onChange(of: wholeWord) { _, _ in result = nil }
            Divider()
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            List {
                ForEach(Array(Set(hits.map(\.file))).sorted(), id: \.self) { file in
                    Section("\(file) · \(hits.filter { $0.file == file }.count) matches") {
                        ForEach(hits.filter { $0.file == file }) { hit in
                            Button { Task { await session.select(hit.file, line: hit.line); session.sheet = nil } } label: {
                                HStack(alignment: .top) { Text("\(hit.line)").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing); Text(hit.excerpt).font(.system(.callout, design: .monospaced)).lineLimit(2) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.listStyle(.inset)
            HStack { Text("\(hits.count) matches in \(Set(hits.map(\.file)).count) files").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Done") { session.sheet = nil }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 860, height: 600)
        .alert("Replace \(hits.count) Matches?", isPresented: $confirmReplace) {
            Button("Cancel", role: .cancel) {}
            Button("Replace All") { replace() }
        } message: { Text("The files listed in the preview will be changed. A complete local snapshot will be created first so the replacement can be restored from History.") }
    }
    private func search() {
        busy = true; error = nil
        let options = SearchOptions(regex: regex, caseSensitive: matchCase, wholeWord: wholeWord); let query = query; let root = session.root
        Task {
            defer { busy = false }
            do { try await session.saveAll(); result = try await Task.detached { try SearchService.search(root: root, query: query, options: options) }.value; searchedQuery = query; searchedOptions = options }
            catch { self.error = error.localizedDescription }
        }
    }
    private func replace() {
        guard let original = result else { return }
        let chosen = currentFile ? SearchResult(hits: hits, documents: original.documents.filter { $0.file == session.selected }) : original
        let root = session.root; let query = searchedQuery; let options = searchedOptions; let replacement = replacement
        busy = true
        Task {
            defer { busy = false }
            do { try await session.saveAll(); _ = try await session.history.snapshot(label: "Before replacing ‘\(query)’"); try await Task.detached { try SearchService.replace(root: root, result: chosen, query: query, replacement: replacement, options: options) }.value; await session.externalChanges(); await session.refreshHistory(); result = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
