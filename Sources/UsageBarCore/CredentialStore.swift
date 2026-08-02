import Foundation
import Security

public enum CredentialParser {
    public static func accessToken(fromJSON data: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (root?["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
    }
}

/// Reads the OAuth token Claude Code already stores. Read-only: this never
/// writes or refreshes credentials — Claude Code keeps them fresh.
public struct CredentialStore {
    public enum CredentialError: Error { case notFound }

    let fallbackURL: URL

    public init(fallbackURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")) {
        self.fallbackURL = fallbackURL
    }

    public func readToken() throws -> String {
        if let data = keychainData(), let token = CredentialParser.accessToken(fromJSON: data) {
            return token
        }
        if let data = try? Data(contentsOf: fallbackURL),
           let token = CredentialParser.accessToken(fromJSON: data) {
            return token
        }
        throw CredentialError.notFound
    }

    private func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
