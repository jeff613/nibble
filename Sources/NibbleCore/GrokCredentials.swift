import Foundation

public struct GrokCredentials: Sendable {
    public enum LookupError: Error, Equatable {
        case notSignedIn
        case malformed
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
    }

    let url: URL

    public init(url: URL = GrokCredentials.defaultURL) {
        self.url = url
    }

    public func readToken() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LookupError.notSignedIn
        }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LookupError.malformed
        }
        for value in root.values {
            guard let entry = value as? [String: Any] else { continue }
            if let key = entry["key"] as? String, !key.isEmpty { return key }
        }
        throw LookupError.notSignedIn
    }
}
