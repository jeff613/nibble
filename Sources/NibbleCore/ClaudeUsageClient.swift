import Foundation

public enum UsageClientError: Error, Equatable {
    case unauthorized
    /// HTTP 429. `retryAfter` carries the server's `Retry-After` header when present.
    case rateLimited(retryAfter: TimeInterval?)
    case badStatus(Int)
}

public final class ClaudeUsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    let session: URLSession
    /// Throws rather than returning nil so the reason a token is unavailable —
    /// notably a locked keychain — reaches the caller intact.
    let tokenProvider: (_ reload: Bool) throws -> String

    public init(
        session: URLSession = .shared,
        tokenProvider: @escaping (_ reload: Bool) throws -> String
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func fetchUsage() async throws -> [LimitWindow] {
        let token = try tokenProvider(false)
        var response = try await request(token: token)

        // A token Claude Code rotated looks exactly like an expired one from
        // here, so spend one retry on a fresh read before reporting failure.
        if response.status == 401 {
            let fresh = try tokenProvider(true)
            if fresh != token { response = try await request(token: fresh) }
        }

        switch response.status {
        case 200:
            return try UsageResponseParser.parse(response.data)
        case 401:
            throw UsageClientError.unauthorized
        case 429:
            throw UsageClientError.rateLimited(retryAfter: response.retryAfter)
        default:
            throw UsageClientError.badStatus(response.status)
        }
    }

    private func request(token: String) async throws
        -> (status: Int, data: Data, retryAfter: TimeInterval?) {
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return (http?.statusCode ?? 0, data, retryAfter)
    }
}
