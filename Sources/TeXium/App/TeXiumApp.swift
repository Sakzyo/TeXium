import SwiftUI
import AppKit

@main
enum TeXiumEntryPoint {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == "--git-credential" {
            GitHubAuthentication.serveCredentialRequest()
        } else { TeXiumApp.main() }
    }
}

struct TeXiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library = ProjectLibrary()
    var body: some Scene {
        WindowGroup("TeXium", id: "browser") {
            ProjectBrowser(library: library)
        }
        .defaultSize(width: 860, height: 560)
        .commands { TeXiumCommands(library: library) }

        WindowGroup("Project", id: "project", for: String.self) { $path in
            if let path { ProjectWindow(root: URL(fileURLWithPath: path), library: library) }
        }
        .defaultSize(width: 1440, height: 900)

        Settings { SettingsView() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSignal: DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume(); terminationSignal = source
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for session in ProjectSession.openSessions.allObjects {
            if session.gitTask != nil {
                let alert = NSAlert(); alert.messageText = "A Git operation is still running"
                alert.informativeText = "Let synchronization finish, or cancel it in the Git inspector, before quitting. A push may already have reached the server."
                alert.addButton(withTitle: "Keep TeXium Open"); alert.runModal(); return .terminateCancel
            }
            do { try session.saveAllSynchronously() }
            catch {
                let alert = NSAlert(); alert.messageText = "Your edits need attention before quitting"
                alert.informativeText = error.localizedDescription + " Your recovery copy is retained."
                alert.addButton(withTitle: "Keep Editing"); alert.runModal()
                return .terminateCancel
            }
            session.stopBuild()
        }
        UserDefaults.standard.set(ProjectSession.openSessions.allObjects.map { $0.root.path }, forKey: "openProjectWindows")
        return .terminateNow
    }
}
