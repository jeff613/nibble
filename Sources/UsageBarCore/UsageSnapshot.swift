import Foundation

/// One quota window reported by the usage endpoint's `limits` array.
public struct LimitWindow: Equatable, Sendable {
    public var kind: String
    public var percent: Double
    public var resetsAt: Date?
    public var severity: String?
    public var modelName: String?

    public init(kind: String, percent: Double, resetsAt: Date? = nil,
                severity: String? = nil, modelName: String? = nil) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.severity = severity
        self.modelName = modelName
    }
}

public enum DateParsing {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ s: String) -> Date? {
        if let d = fractional.date(from: s) ?? plain.date(from: s) { return d }
        // ISO8601DateFormatter accepts exactly 3 fractional digits; the API sends 6.
        if let dotRange = s.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = s[dotRange].dropFirst()
            let trimmed = s.replacingCharacters(in: dotRange, with: "." + digits.prefix(3))
            return fractional.date(from: trimmed)
        }
        return nil
    }
}

/// Parses the `limits` array generically so new or renamed windows appear
/// without code changes, and malformed entries are skipped rather than fatal.
public enum UsageResponseParser {
    public enum ParseError: Error { case missingLimits }

    public static func parse(_ data: Data) throws -> [LimitWindow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let limits = root?["limits"] as? [[String: Any]] else {
            throw ParseError.missingLimits
        }
        return limits.compactMap { entry in
            guard let kind = entry["kind"] as? String,
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue else { return nil }
            let resetsAt = (entry["resets_at"] as? String).flatMap(DateParsing.parse)
            let severity = entry["severity"] as? String
            let scope = entry["scope"] as? [String: Any]
            let modelName = (scope?["model"] as? [String: Any])?["display_name"] as? String
            return LimitWindow(kind: kind, percent: percent, resetsAt: resetsAt,
                               severity: severity, modelName: modelName)
        }
    }
}
