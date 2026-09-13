import AppKit
import UniformTypeIdentifiers
import TeXiumCore

extension ProjectSession {
    var selectedFolder: String {
        guard let selected else { return "" }
        if ProjectFileSystem.flatten(nodes).first(where: { $0.path == selected })?.isDirectory == true { return selected }
        let path = (selected as NSString).deletingLastPathComponent
        return path == "." ? "" : path
    }
    func createItem(name: String, folder: Bool) async {
        guard !operationBusy else { return }; operationBusy = true
        defer { operationBusy = false }
        do {
            try ProjectFileSystem.validateName(name)
            let path = selectedFolder.isEmpty ? name : selectedFolder + "/" + name
            let url = try ProjectFileSystem.resolve(path, in: root)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw TeXiumError.message("An item named \(name) already exists.") }
            if folder { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
            else { try Data().write(to: url, options: .withoutOverwriting) }
            await refreshIndex(); if !folder { await select(path) }; sheet = nil
        } catch { present(error) }
    }
    func renameItem(_ path: String, to name: String) async {
        guard !operationBusy else { return }; operationBusy = true
        defer { operationBusy = false }
        do {
            try ProjectFileSystem.validateName(name); try await saveAll()
            _ = try await history.snapshot(label: "Before renaming \(path)")
            let from = try ProjectFileSystem.resolve(path, in: root); let to = from.deletingLastPathComponent().appendingPathComponent(name)
            try FileManager.default.moveItem(at: from, to: to)
            let newPath = try ProjectFileSystem.relative(to, to: root)
            if configuration.mainFile == path { configuration.mainFile = newPath }
            else if configuration.mainFile.hasPrefix(path + "/") { configuration.mainFile = newPath + configuration.mainFile.dropFirst(path.count) }
            buffers = buffers.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }; tabs.removeAll { $0 == path || $0.hasPrefix(path + "/") }
            await refreshIndex(); await select(newPath); persistPreferences(); sheet = nil
        } catch { present(error) }
    }
    func duplicateItem(_ path: String) async {
        guard !operationBusy else { return }; operationBusy = true
        defer { operationBusy = false }
        do {
            try await saveAll(); let source = try ProjectFileSystem.resolve(path, in: root)
            let name = source.deletingPathExtension().lastPathComponent + " Copy" + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension)
            let target = source.deletingLastPathComponent().appendingPathComponent(name)
            try await Task.detached { try FileManager.default.copyItem(at: source, to: target) }.value; await refreshIndex()
        } catch { present(error) }
    }
    func trashItem(_ path: String) async {
        guard !operationBusy else { return }; operationBusy = true
        defer { operationBusy = false }
        do {
            try await saveAll(); _ = try await history.snapshot(label: "Before moving \(path) to Trash")
            let url = try ProjectFileSystem.resolve(path, in: root)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            buffers = buffers.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }; tabs.removeAll { $0 == path || $0.hasPrefix(path + "/") }
            if selected == path || selected?.hasPrefix(path + "/") == true { selected = tabs.last }
            await refreshIndex(); await refreshHistory()
        } catch { present(error) }
    }
    func importFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        if panel.runModal() == .OK { let urls = panel.urls; Task { await importURLs(urls, folder: selectedFolder, move: false) } }
    }
    func importURLs(_ urls: [URL], folder: String, move: Bool) async {
        guard !operationBusy else { return }; operationBusy = true
        defer { operationBusy = false }
        do {
            try await saveAll(); _ = try await history.snapshot(label: "Before importing or moving files")
            let directory = folder.isEmpty ? root : try ProjectFileSystem.resolve(folder, in: root)
            for source in urls {
                let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                try ProjectFileSystem.validateName(source.lastPathComponent)
                let target = directory.appendingPathComponent(source.lastPathComponent)
                guard source.standardizedFileURL != target.standardizedFileURL else { continue }
                guard !target.path.hasPrefix(source.path + "/") else { throw TeXiumError.message("A folder cannot be moved inside itself.") }
                guard !FileManager.default.fileExists(atPath: target.path) else { throw TeXiumError.message("\(target.lastPathComponent) already exists. Rename it before importing another copy.") }
                if move, (try? ProjectFileSystem.relative(source, to: root)) != nil {
                    let path = try ProjectFileSystem.relative(source, to: root)
                    try FileManager.default.moveItem(at: source, to: target)
                    let newPath = try ProjectFileSystem.relative(target, to: root)
                    if configuration.mainFile == path { configuration.mainFile = newPath }
                    else if configuration.mainFile.hasPrefix(path + "/") { configuration.mainFile = newPath + configuration.mainFile.dropFirst(path.count) }
                    buffers = buffers.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }; tabs.removeAll { $0 == path || $0.hasPrefix(path + "/") }
                } else { try await Task.detached { try FileManager.default.copyItem(at: source, to: target) }.value }
            }
            await refreshIndex(); persistPreferences()
        } catch { present(error) }
    }
    func acceptDrop(_ providers: [NSItemProvider], folder: String, move: Bool) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSURL.self) { [weak self] value, _ in
                guard let url = value as? URL else { return }
                Task { @MainActor in await self?.importURLs([url], folder: folder, move: move) }
            }
        }
        return !providers.isEmpty
    }
    func exportPDF() {
        guard let pdf = pdfURL else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = title + ".pdf"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        Task { do { try await Task.detached { try Data(contentsOf: pdf).write(to: target, options: .atomic) }.value } catch { present(error) } }
    }
    func saveBuildLog() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "build.log"
        if panel.runModal() == .OK, let url = panel.url { do { try buildLog.write(to: url, atomically: true, encoding: .utf8) } catch { present(error) } }
    }
}
