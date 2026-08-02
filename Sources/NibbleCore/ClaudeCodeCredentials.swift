import Foundation
import Security

/// Reads the OAuth token Claude Code stores on this Mac.
///
/// Nibble only does this after the user explicitly asks it to, and macOS shows
/// its own permission prompt the first time. Nothing is copied: the token is read
/// live on each request, so it stays fresh as Claude Code rotates it, and Nibble
/// never writes, refreshes, or persists a credential of its own.
public struct ClaudeCodeCredentials {
    public enum LookupError: Error, LocalizedError, Equatable {
        case notSignedIn
        case accessDenied
        case keychain(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "No Claude Code login found on this Mac. Run `claude` and sign in first."
            case .accessDenied:
                return "macOS denied access to the Claude Code login. Approve the prompt, or allow Nibble in Keychain Access."
            case .keychain(let status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
                return "Keychain error: \(detail)"
            }
        }
    }

    static let keychainService = "Claude Code-credentials"

    let fallbackURL: URL
    let useKeychain: Bool

    public init(
        fallbackURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json"),
        useKeychain: Bool = true
    ) {
        self.fallbackURL = fallbackURL
        self.useKeychain = useKeychain
    }

    /// Extracts the access token from Claude Code's credential JSON.
    public static func accessToken(fromJSON data: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let token = (root?["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
        return (token?.isEmpty ?? true) ? nil : token
    }

    public func readToken() throws -> String {
        if useKeychain {
            switch keychainToken() {
            case .success(let token):
                return token
            case .failure(.notSignedIn):
                break  // fall through to the JSON file
            case .failure(let error):
                throw error
            }
        }
        if let data = try? Data(contentsOf: fallbackURL),
           let token = Self.accessToken(fromJSON: data) {
            return token
        }
        throw LookupError.notSignedIn
    }

    private func keychainToken() -> Result<String, LookupError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = Self.accessToken(fromJSON: data) else {
                return .failure(.notSignedIn)
            }
            return .success(token)
        case errSecItemNotFound:
            return .failure(.notSignedIn)
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .failure(.accessDenied)
        default:
            return .failure(.keychain(status))
        }
    }
}
