import Foundation
import Security

public struct GitHubCredentialStore: Sendable {
    public let service: String
    public init(service: String = "app.texium.mac.github") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    public func save(token: String, account: String) throws {
        guard GitHubRepository.validAccount(account), !token.isEmpty,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }), !token.contains("\0") else {
            throw TeXiumError.message("Enter your GitHub username and a personal access token without spaces or line breaks.")
        }
        let data = Data(token.utf8)
        var status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account); item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "TeXium GitHub · " + account
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        try check(status)
    }
    public func token(account: String) throws -> String? {
        var request = query(account); request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }
    public func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            throw TeXiumError.message("macOS Keychain could not complete the request: " + message)
        }
    }
}

/// Git's credential protocol is kept separate from Keychain for bounded tests.
/// Only the exact HTTPS GitHub context can request the configured credential.
public enum GitHubCredentialProtocol {
    public static func response(input: String, action: String, account: String, readToken: () throws -> String?) throws -> String {
        guard action == "get", GitHubRepository.validAccount(account), input.utf8.count <= 16_384 else { return "" }
        var fields: [String: String] = [:]
        for line in input.components(separatedBy: "\n") {
            if line.isEmpty { break }
            guard !line.contains("\r"), !line.contains("\0"), let separator = line.firstIndex(of: "=") else { return "" }
            let key = String(line[..<separator]); let value = String(line[line.index(after: separator)...])
            guard fields[key] == nil else { return "" }; fields[key] = value
        }
        guard fields["protocol"] == "https", fields["host"] == "github.com",
              fields["username"] == nil || fields["username"]?.lowercased() == account.lowercased(),
              let token = try readToken(), !token.isEmpty, !token.contains(where: { $0.isWhitespace }), !token.contains("\0") else { return "" }
        return "username=\(account)\npassword=\(token)\n\n"
    }
}
