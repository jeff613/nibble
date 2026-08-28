import Foundation

public struct CodexToken: Equatable, Sendable {
    public var accessToken: String
    public var accountID: String?
}

public struct CodexCredentials: Sendable {
    public enum LookupError: Error, Equatable {
        case notSignedIn
        case malformed
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    let url: URL

    public init(url: URL = CodexCredentials.defaultURL) {
        self.url = url
    }

    public func readToken() throws -> CodexToken {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LookupError.notSignedIn
        }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LookupError.malformed
        }
        let tokens = root["tokens"] as? [String: Any]
        let access = tokens?["access_token"] as? String ?? ""
        guard !access.isEmpty else { throw LookupError.notSignedIn }
        let account = tokens?["account_id"] as? String
        return CodexToken(accessToken: access, accountID: account?.isEmpty == true ? nil : account)
    }
}
