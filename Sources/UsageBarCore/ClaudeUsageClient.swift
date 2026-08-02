import Foundation

public enum UsageClientError: Error {
    case unauthorized
    case badStatus(Int)
}

public final class ClaudeUsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    let session: URLSession
    let tokenProvider: () throws -> String

    public init(session: URLSession = .shared, tokenProvider: @escaping () throws -> String) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func fetchUsage() async throws -> [LimitWindow] {
        let first = try await request(token: tokenProvider())
        if first.status == 401 {
            // The token may have rotated since we read it — re-read once and retry.
            let second = try await request(token: tokenProvider())
            guard second.status != 401 else { throw UsageClientError.unauthorized }
            return try handle(second)
        }
        return try handle(first)
    }

    private func request(token: String) async throws -> (status: Int, data: Data) {
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, resp) = try await session.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private func handle(_ r: (status: Int, data: Data)) throws -> [LimitWindow] {
        guard r.status == 200 else { throw UsageClientError.badStatus(r.status) }
        return try UsageResponseParser.parse(r.data)
    }
}
