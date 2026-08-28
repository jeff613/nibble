import Foundation

public enum CodexUsageParser {
    public static func parse(_ data: Data, now: Date = Date()) -> [LimitWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        let rate = root["rate_limit"] as? [String: Any] ?? [:]
        var windows: [LimitWindow] = []
        for key in ["primary_window", "secondary_window"] {
            if let raw = rate[key] as? [String: Any],
               let window = window(from: raw, now: now) {
                windows.append(window)
            }
        }
        if let credits = root["credits"] as? [String: Any],
           credits["has_credits"] as? Bool == true,
           credits["unlimited"] as? Bool != true,
           let percent = number(credits["used_percent"]) {
            windows.append(LimitWindow(kind: "credits", percent: percent))
        }
        return windows
    }

    private static func window(from raw: [String: Any], now: Date) -> LimitWindow? {
        guard let percent = number(raw["used_percent"]) else { return nil }
        let minutes = number(raw["window_minutes"])
            ?? number(raw["limit_window_seconds"]).map { $0 / 60 }
        guard let minutes, let kind = kind(minutes: minutes) else { return nil }
        let resetsAt: Date?
        if let unix = number(raw["reset_at"]) {
            resetsAt = Date(timeIntervalSince1970: unix)
        } else if let after = number(raw["reset_after_seconds"]) {
            resetsAt = now.addingTimeInterval(after)
        } else {
            resetsAt = nil
        }
        return LimitWindow(kind: kind, percent: percent, resetsAt: resetsAt)
    }

    private static func kind(minutes: Double) -> String? {
        switch minutes {
        case 240...360: return "session"
        case 9000...12000: return "weekly"
        default: return nil
        }
    }

    private static func number(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }
}

public final class CodexUsageClient {
    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    let session: URLSession
    let tokenProvider: (_ reload: Bool) throws -> CodexToken

    public init(
        session: URLSession = .shared,
        tokenProvider: @escaping (_ reload: Bool) throws -> CodexToken
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func fetchUsage() async throws -> [LimitWindow] {
        let token = try tokenProvider(false)
        var response = try await request(token)
        if response.status == 401 {
            let fresh = try tokenProvider(true)
            if fresh.accessToken != token.accessToken { response = try await request(fresh) }
        }
        switch response.status {
        case 200:
            return CodexUsageParser.parse(response.data)
        case 401:
            throw UsageClientError.unauthorized
        case 429:
            throw UsageClientError.rateLimited(retryAfter: response.retryAfter)
        default:
            throw UsageClientError.badStatus(response.status)
        }
    }

    private func request(_ token: CodexToken) async throws
        -> (status: Int, data: Data, retryAfter: TimeInterval?) {
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        if let id = token.accountID {
            req.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return (http?.statusCode ?? 0, data, retryAfter)
    }
}
