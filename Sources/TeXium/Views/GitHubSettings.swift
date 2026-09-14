import SwiftUI
import TeXiumCore

struct GitHubSettings: View {
    @AppStorage("gitHubAccount") private var savedAccount = ""
    @State private var account = ""
    @State private var token = ""
    @State private var message = ""
    @State private var busy = false
    @State private var failed = false
    var body: some View {
        Form {
            Section("GitHub HTTPS Authentication") {
                TextField("GitHub username", text: $account).textContentType(.username)
                SecureField("Personal access token", text: $token).textContentType(.password)
                Text("The token is stored only in this app’s macOS Keychain item. It is sent to GitHub by Git when you explicitly fetch, clone, pull, or push.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save to Keychain") { save() }.disabled(account.isEmpty || token.isEmpty || busy)
                    if !savedAccount.isEmpty { Button("Remove Token", role: .destructive) { remove() }.disabled(busy) }
                }
                if !savedAccount.isEmpty { Label("Configured for \(savedAccount)", systemImage: "lock.fill").font(.caption) }
                if !message.isEmpty { Label(message, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle").font(.caption).textSelection(.enabled) }
            }
            Section("Access and SSH") {
                Text("For a fine-grained token, select the repositories you need and allow Contents read/write to push. Organization approval may also be required. GitHub enforces repository permissions and branch protection.").font(.caption)
                Link("Manage GitHub Access Tokens", destination: URL(string: "https://github.com/settings/personal-access-tokens")!)
                Text("SSH URLs use your existing SSH key and agent. Without a TeXium token, HTTPS uses your configured Git credential helper. No account is needed for local editing or public clones.").font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { account = savedAccount }
    }
    private func save() {
        busy = true; failed = false; message = ""
        let name = account.trimmingCharacters(in: .whitespacesAndNewlines); let secret = token; let store = GitHubAuthentication.store
        Task {
            defer { busy = false }
            do {
                try await Task.detached { try store.save(token: secret, account: name) }.value
                savedAccount = name; token = ""; message = "Saved securely. Fetch a connected repository to test access."
            } catch { failed = true; message = error.localizedDescription }
        }
    }
    private func remove() {
        busy = true; failed = false; let name = savedAccount; let store = GitHubAuthentication.store
        Task {
            defer { busy = false }
            do { try await Task.detached { try store.remove(account: name) }.value; savedAccount = ""; token = ""; message = "The TeXium token was removed from Keychain." }
            catch { failed = true; message = error.localizedDescription }
        }
    }
}
