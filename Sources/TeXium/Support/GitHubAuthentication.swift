import Foundation
import TeXiumCore

enum GitHubAuthentication {
    static var store: GitHubCredentialStore {
        GitHubCredentialStore(service: (Bundle.main.bundleIdentifier ?? "app.texium.mac") + ".github")
    }
    static var configured: GitAuthentication? {
        guard let account = UserDefaults.standard.string(forKey: "gitHubAccount"), GitHubRepository.validAccount(account),
              let executable = Bundle.main.executableURL else { return nil }
        return GitAuthentication(executable: executable, account: account)
    }
    static func forRemote(_ remote: String) -> GitAuthentication? {
        guard let repository = try? GitHubRepository(remote), !repository.usesSSH else { return nil }
        return configured
    }
    static func serveCredentialRequest() {
        guard CommandLine.arguments.count == 3 else { return }
        let action = CommandLine.arguments[2]
        guard action == "get" else { return } // Native Settings alone owns writes.
        var input = ""
        while let line = readLine(strippingNewline: true), !line.isEmpty {
            input += line + "\n"
            guard input.utf8.count <= 16_384 else { return }
        }
        let account = UserDefaults.standard.string(forKey: "gitHubAccount") ?? ""
        do {
            let response = try GitHubCredentialProtocol.response(input: input, action: action, account: account) { try store.token(account: account) }
            // The token goes directly to Git's private pipe, never to arguments,
            // environment variables, project files, or application logs.
            FileHandle.standardOutput.write(Data(response.utf8))
        } catch {
            FileHandle.standardError.write(Data("TeXium could not unlock the GitHub credential. Open Settings → GitHub to reconnect.\n".utf8))
        }
    }
}
