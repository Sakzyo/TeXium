import SwiftUI
import AppKit
import TeXiumCore

struct RecentProject: Identifiable, Codable {
    var path: String
    var opened: Date
    var favorite = false
    var bookmark: Data?
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var available: Bool { FileManager.default.fileExists(atPath: path) }
    var modified: Date? { (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
}
@MainActor @Observable final class ProjectLibrary {
    var recents: [RecentProject] = []
    var error: String?
    var createRequested = false
    var restoredLaunch = false
    init() {
        if let data = UserDefaults.standard.data(forKey: "recentProjects") { recents = (try? JSONDecoder().decode([RecentProject].self, from: data)) ?? [] }
    }
    func remember(_ url: URL) {
        let old = recents.first(where: { $0.path == url.path })
        recents.removeAll { $0.path == url.path }
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        recents.insert(RecentProject(path: url.path, opened: Date(), favorite: old?.favorite ?? false, bookmark: bookmark), at: 0)
        persist(); NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
    func resolve(_ recent: RecentProject) throws -> URL {
        if let data = recent.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        guard recent.available else { throw TeXiumError.message("This project is unavailable. Reconnect its drive or use Open Project to locate the moved folder and renew access.") }
        return URL(fileURLWithPath: recent.path)
    }
    func persist() { if let data = try? JSONEncoder().encode(recents) { UserDefaults.standard.set(data, forKey: "recentProjects") } }
    func remove(_ recent: RecentProject) { recents.removeAll { $0.id == recent.id }; persist() }
    func favorite(_ recent: RecentProject) {
        if let index = recents.firstIndex(where: { $0.id == recent.id }) { recents[index].favorite.toggle(); persist() }
    }
    func chooseProject() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Open Project"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
