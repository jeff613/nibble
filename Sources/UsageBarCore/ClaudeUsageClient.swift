import Foundation

public enum UsageClientError: Error, Equatable {
    case notConfigured
    case unauthorized
    /// HTTP 429. `retryAfter` carries the server's `Retry-After` header when present.
    case rateLimited(retryAfter: TimeInterval?)
    case badStatus(Int)
}

public final class ClaudeUsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    let session: URLSession
    let tokenProvider: () -> String?

    public init(session: URLSession = .shared, tokenProvider: @escaping () -> String?) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func fetchUsage() async throws -> [LimitWindow] {
        guard let token = tokenProvider() else { throw UsageClientError.notConfigured }
        let response = try await request(token: token)

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
