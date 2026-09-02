import Foundation

public enum GrokUsageParser {
    public static func parse(_ data: Data) -> [LimitWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        let config = (root["config"] as? [String: Any]) ?? root
        // The server drops creditUsagePercent while it is zero, so a period
        // with no percent is 0% used, not "no data".
        guard let period = config["currentPeriod"] as? [String: Any] else { return [] }
        let percent = (config["creditUsagePercent"] as? NSNumber)?.doubleValue ?? 0
        let type = (period["type"] as? String) ?? ""
        let kind = type.contains("MONTHLY") ? "monthly" : "weekly"
        let resetsAt = (period["end"] as? String).flatMap(DateParsing.parse)
        return [LimitWindow(kind: kind, percent: percent, resetsAt: resetsAt)]
    }
}

public final class GrokUsageClient {
    static let endpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    let session: URLSession
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
        var response = try await request(token)
        if response.status == 401 {
            let fresh = try tokenProvider(true)
            if fresh != token { response = try await request(fresh) }
        }
        switch response.status {
        case 200:
            return GrokUsageParser.parse(response.data)
        case 401:
            throw UsageClientError.unauthorized
        case 429:
            throw UsageClientError.rateLimited(retryAfter: response.retryAfter)
        default:
            throw UsageClientError.badStatus(response.status)
        }
    }

    private func request(_ token: String) async throws
        -> (status: Int, data: Data, retryAfter: TimeInterval?) {
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        req.setValue("xai-grok-cli", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return (http?.statusCode ?? 0, data, retryAfter)
    }
}
