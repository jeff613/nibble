# Claude Usage Menu-Bar App (UsageBar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar app showing near-real-time Claude subscription quota (5-hour / weekly / Fable-weekly windows) with a click-open panel showing gauges, reset countdowns, a 7-day token chart, and an API-price cost estimate.

**Architecture:** Swift Package with two targets: `UsageBarCore` (pure logic: JSON decoding, JSONL scanning, formatting, pricing, refresh policy — fully unit-tested) and `UsageBar` (thin executable: AppKit status item + SwiftUI popover + wiring — verified by running). Live quota comes from Anthropic's OAuth usage endpoint using the token Claude Code stores in the Keychain; history comes from `~/.claude/projects/**/*.jsonl`.

**Tech Stack:** Swift 5.9+, SwiftPM only (no Xcode project), macOS 14+, AppKit `NSStatusItem` + SwiftUI + Swift Charts. Zero external dependencies.

## Global Constraints

- macOS 14+, Swift 5.9+, SwiftPM only (`swift build` / `swift test`), **no external dependencies**.
- App name: **UsageBar**. Bundle ID: `com.jeff613.usagebar`. Menu-bar only (`LSUIElement`).
- Credentials are **read-only**: never write, refresh, or mutate the Claude Code token.
- Endpoint: `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.
- Parse the response's `limits` array generically (not the fixed top-level fields). Malformed entries are skipped, never fatal.
- `UsageBarCore` must not import AppKit/SwiftUI (keeps tests headless).
- Pricing table ($/MTok): fable|mythos → 10 in / 50 out; opus → 5/25; sonnet → 3/15; haiku → 1/5. Cache write = 1.25 × input rate, cache read = 0.1 × input rate. Unknown model → no pricing (tokens still counted, cost excluded).
- Commit after every task with a conventional message.

---

### Task 1: Package scaffold + usage response decoding

**Files:**
- Create: `Package.swift`
- Create: `Sources/UsageBarCore/UsageSnapshot.swift`
- Create: `Sources/UsageBar/main.swift` (placeholder so the package builds)
- Test: `Tests/UsageBarTests/UsageDecodingTests.swift`

**Interfaces:**
- Produces: `struct LimitWindow: Equatable, Sendable { var kind: String; var percent: Double; var resetsAt: Date?; var severity: String?; var modelName: String? }`
- Produces: `enum UsageResponseParser { static func parse(_ data: Data) throws -> [LimitWindow] }`
- Produces: `enum DateParsing { static func parse(_ s: String) -> Date? }` (handles 6-digit fractional seconds and `Z`/`+00:00` offsets)

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageBarCore"),
        .executableTarget(name: "UsageBar", dependencies: ["UsageBarCore"]),
        .testTarget(name: "UsageBarTests", dependencies: ["UsageBarCore"]),
    ]
)
```

`Sources/UsageBar/main.swift` placeholder:

```swift
print("UsageBar placeholder — replaced in Task 8")
```

- [ ] **Step 2: Write the failing test**

Use a fixture captured from the real endpoint (trimmed):

```swift
import XCTest
@testable import UsageBarCore

final class UsageDecodingTests: XCTestCase {
    static let fixture = Data("""
    {
      "five_hour": {"utilization": 88.0, "resets_at": "2026-08-02T09:20:00.953490+00:00"},
      "seven_day_opus": null,
      "limits": [
        {"kind": "session", "group": "session", "percent": 88, "severity": "warning",
         "resets_at": "2026-08-02T09:20:00.347559+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_all", "group": "weekly", "percent": 75, "severity": "warning",
         "resets_at": "2026-08-02T11:00:00.347578+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 81, "severity": "warning",
         "resets_at": "2026-08-02T11:00:00.347793+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false},
        {"kind": "future_unknown_thing", "percent": "not-a-number"}
      ]
    }
    """.utf8)

    func testParsesLimitsArray() throws {
        let windows = try UsageResponseParser.parse(Self.fixture)
        XCTAssertEqual(windows.count, 3)  // malformed 4th entry skipped
        XCTAssertEqual(windows[0].kind, "session")
        XCTAssertEqual(windows[0].percent, 88)
        XCTAssertEqual(windows[2].modelName, "Fable")
        XCTAssertNil(windows[1].modelName)
        XCTAssertNotNil(windows[0].resetsAt)
    }

    func testParsesFractionalSecondsDate() {
        let d = DateParsing.parse("2026-08-02T09:20:00.953490+00:00")
        XCTAssertNotNil(d)
        let z = DateParsing.parse("2026-08-01T22:15:03.123Z")
        XCTAssertNotNil(z)
    }

    func testMissingLimitsThrows() {
        XCTAssertThrowsError(try UsageResponseParser.parse(Data("{}".utf8)))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `UsageResponseParser` not found.

- [ ] **Step 4: Write minimal implementation**

`Sources/UsageBarCore/UsageSnapshot.swift`:

```swift
import Foundation

public struct LimitWindow: Equatable, Sendable {
    public var kind: String
    public var percent: Double
    public var resetsAt: Date?
    public var severity: String?
    public var modelName: String?

    public init(kind: String, percent: Double, resetsAt: Date? = nil,
                severity: String? = nil, modelName: String? = nil) {
        self.kind = kind; self.percent = percent; self.resetsAt = resetsAt
        self.severity = severity; self.modelName = modelName
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
        // ISO8601DateFormatter only accepts exactly 3 fractional digits, so
        // trim 6-digit microseconds down to milliseconds before parsing.
        if let d = fractional.date(from: s) ?? plain.date(from: s) { return d }
        if let dotRange = s.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = s[dotRange].dropFirst()
            let trimmed = s.replacingCharacters(in: dotRange, with: "." + digits.prefix(3))
            return fractional.date(from: trimmed)
        }
        return nil
    }
}

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
            let modelName = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
            return LimitWindow(kind: kind, percent: percent, resetsAt: resetsAt,
                               severity: severity, modelName: modelName)
        }
    }
}
```

(JSONSerialization is used deliberately: the `limits` entries are heterogeneous and per-entry skip-on-malformed is simpler than Codable failable wrappers.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: package scaffold and usage endpoint decoding"
```

---

### Task 2: Bar text, severity level, and countdown formatting

**Files:**
- Create: `Sources/UsageBarCore/Formatting.swift`
- Test: `Tests/UsageBarTests/FormattingTests.swift`

**Interfaces:**
- Consumes: `LimitWindow` (Task 1)
- Produces: `enum Severity: Comparable { case normal, warning, critical }`
- Produces: `enum Formatting { static func barText(_ windows: [LimitWindow]) -> String; static func severity(_ windows: [LimitWindow]) -> Severity; static func shortLabel(_ w: LimitWindow) -> String; static func countdown(until: Date, now: Date) -> String; static func sorted(_ windows: [LimitWindow]) -> [LimitWindow] }`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import UsageBarCore

final class FormattingTests: XCTestCase {
    let windows = [
        LimitWindow(kind: "weekly_scoped", percent: 81, modelName: "Fable"),
        LimitWindow(kind: "session", percent: 88),
        LimitWindow(kind: "weekly_all", percent: 75),
    ]

    func testBarTextOrderAndLabels() {
        XCTAssertEqual(Formatting.barText(windows), "5h 88% · wk 75% · F 81%")
    }

    func testBarTextEmpty() {
        XCTAssertEqual(Formatting.barText([]), "—")
    }

    func testUnknownKindUsesKindPrefix() {
        let w = [LimitWindow(kind: "monthly_all", percent: 10)]
        XCTAssertEqual(Formatting.barText(w), "mo 10%")
    }

    func testSeverityThresholds() {
        XCTAssertEqual(Formatting.severity([LimitWindow(kind: "session", percent: 50)]), .normal)
        XCTAssertEqual(Formatting.severity([LimitWindow(kind: "session", percent: 75)]), .warning)
        XCTAssertEqual(Formatting.severity(windows), .warning)
        XCTAssertEqual(Formatting.severity([LimitWindow(kind: "session", percent: 92)]), .critical)
        XCTAssertEqual(Formatting.severity([]), .normal)
    }

    func testCountdown() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(2 * 3600 + 14 * 60), now: now), "resets in 2h 14m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(14 * 60), now: now), "resets in 14m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(30), now: now), "resets in <1m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(-5), now: now), "resetting…")
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -20`

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum Severity: Int, Comparable, Sendable {
    case normal, warning, critical
    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

public enum Formatting {
    static let kindOrder = ["session": 0, "weekly_all": 1, "weekly_scoped": 2]

    public static func sorted(_ windows: [LimitWindow]) -> [LimitWindow] {
        windows.sorted { (kindOrder[$0.kind] ?? 99) < (kindOrder[$1.kind] ?? 99) }
    }

    public static func shortLabel(_ w: LimitWindow) -> String {
        switch w.kind {
        case "session": return "5h"
        case "weekly_all": return "wk"
        case "weekly_scoped": return w.modelName.map { String($0.prefix(1)) } ?? "m"
        default: return String(w.kind.prefix(2))
        }
    }

    public static func barText(_ windows: [LimitWindow]) -> String {
        guard !windows.isEmpty else { return "—" }
        return sorted(windows)
            .map { "\(shortLabel($0)) \(Int($0.percent.rounded()))%" }
            .joined(separator: " · ")
    }

    public static func severity(_ windows: [LimitWindow]) -> Severity {
        let worst = windows.map(\.percent).max() ?? 0
        if worst >= 90 { return .critical }
        if worst >= 75 { return .warning }
        return .normal
    }

    public static func countdown(until: Date, now: Date) -> String {
        let s = until.timeIntervalSince(now)
        guard s > 0 else { return "resetting…" }
        let minutes = Int(s / 60)
        if minutes < 1 { return "resets in <1m" }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }
}
```

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: bar text, severity, and countdown formatting"`

---

### Task 3: Credential store (Keychain + file fallback)

**Files:**
- Create: `Sources/UsageBarCore/CredentialStore.swift`
- Test: `Tests/UsageBarTests/CredentialTests.swift`

**Interfaces:**
- Produces: `enum CredentialParser { static func accessToken(fromJSON data: Data) -> String? }`
- Produces: `struct CredentialStore { init(); func readToken() throws -> String }` — reads Keychain generic password `service="Claude Code-credentials"`, falls back to `~/.claude/.credentials.json`. `enum CredentialError: Error { case notFound }`

- [ ] **Step 1: Write failing tests (parser only — Keychain is untestable glue)**

```swift
import XCTest
@testable import UsageBarCore

final class CredentialTests: XCTestCase {
    func testExtractsAccessToken() {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"x"}}"#.utf8)
        XCTAssertEqual(CredentialParser.accessToken(fromJSON: json), "sk-ant-oat01-abc")
    }

    func testReturnsNilForGarbage() {
        XCTAssertNil(CredentialParser.accessToken(fromJSON: Data("nope".utf8)))
        XCTAssertNil(CredentialParser.accessToken(fromJSON: Data("{}".utf8)))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -10`

- [ ] **Step 3: Implement**

```swift
import Foundation
import Security

public enum CredentialParser {
    public static func accessToken(fromJSON data: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (root?["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
    }
}

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
```

Note: the first Keychain read from the app triggers a one-time macOS permission prompt ("UsageBar wants to access…"). The user should click **Always Allow**. This is expected and documented in the final README step.

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: credential store with keychain and file fallback"`

---

### Task 4: Usage client with 401 re-read retry

**Files:**
- Create: `Sources/UsageBarCore/ClaudeUsageClient.swift`
- Test: `Tests/UsageBarTests/UsageClientTests.swift`

**Interfaces:**
- Consumes: `UsageResponseParser`, `LimitWindow` (Task 1)
- Produces: `final class ClaudeUsageClient { init(session: URLSession = .shared, tokenProvider: @escaping () throws -> String); func fetchUsage() async throws -> [LimitWindow] }`
- Produces: `enum UsageClientError: Error { case unauthorized, badStatus(Int) }`

- [ ] **Step 1: Write failing tests using a URLProtocol stub**

```swift
import XCTest
@testable import UsageBarCore

final class StubProtocol: URLProtocol {
    // Queue of (status, body) responses; consumed one per request.
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var seenAuthHeaders: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seenAuthHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let (status, body) = Self.responses.isEmpty ? (500, Data()) : Self.responses.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class UsageClientTests: XCTestCase {
    func makeClient(tokens: [String]) -> ClaudeUsageClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        var remaining = tokens
        return ClaudeUsageClient(session: URLSession(configuration: config)) {
            remaining.isEmpty ? tokens.last! : remaining.removeFirst()
        }
    }

    override func setUp() {
        StubProtocol.responses = []
        StubProtocol.seenAuthHeaders = []
    }

    func testFetchParsesWindows() async throws {
        StubProtocol.responses = [(200, UsageDecodingTests.fixture)]
        let windows = try await makeClient(tokens: ["tok1"]).fetchUsage()
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(StubProtocol.seenAuthHeaders, ["Bearer tok1"])
    }

    func testRetriesOnceOn401WithFreshToken() async throws {
        StubProtocol.responses = [(401, Data()), (200, UsageDecodingTests.fixture)]
        let windows = try await makeClient(tokens: ["stale", "fresh"]).fetchUsage()
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(StubProtocol.seenAuthHeaders, ["Bearer stale", "Bearer fresh"])
    }

    func testThrowsUnauthorizedAfterSecond401() async {
        StubProtocol.responses = [(401, Data()), (401, Data())]
        do {
            _ = try await makeClient(tokens: ["a", "b"]).fetchUsage()
            XCTFail("should throw")
        } catch let e as UsageClientError {
            guard case .unauthorized = e else { return XCTFail("wrong error \(e)") }
        } catch { XCTFail("wrong error \(error)") }
    }
}
```

(Make `UsageDecodingTests.fixture` `static let` — done in Task 1.)

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum UsageClientError: Error { case unauthorized, badStatus(Int) }

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
            // Token may have rotated since we read it — re-read once and retry.
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
```

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: usage client with 401 token re-read retry"`

---

### Task 5: JSONL line parsing and day/model aggregation

**Files:**
- Create: `Sources/UsageBarCore/UsageHistory.swift`
- Test: `Tests/UsageBarTests/UsageHistoryTests.swift`

**Interfaces:**
- Produces: `struct UsageEvent: Equatable { var timestamp: Date; var model: String; var dedupeKey: String?; var input: Int; var output: Int; var cacheCreation: Int; var cacheRead: Int }`
- Produces: `enum UsageLineParser { static func parse(_ line: String) -> UsageEvent? }`
- Produces: `struct DayModelKey: Hashable { var day: String; var model: String }`
- Produces: `struct TokenCounts: Equatable { var input: Int; var output: Int; var cacheCreation: Int; var cacheRead: Int; var total: Int { get }; mutating func add(_ e: UsageEvent) }`
- Produces: `enum UsageAggregator { static func dayKey(for date: Date, timeZone: TimeZone) -> String; static func fold(events: [UsageEvent], into totals: inout [DayModelKey: TokenCounts], seen: inout Set<String>, timeZone: TimeZone) }`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import UsageBarCore

final class UsageHistoryTests: XCTestCase {
    let assistantLine = #"{"type":"assistant","timestamp":"2026-08-01T10:00:00.000Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-fable-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}"#

    func testParsesAssistantLine() throws {
        let e = try XCTUnwrap(UsageLineParser.parse(assistantLine))
        XCTAssertEqual(e.model, "claude-fable-5")
        XCTAssertEqual(e.input, 10)
        XCTAssertEqual(e.output, 20)
        XCTAssertEqual(e.cacheCreation, 100)
        XCTAssertEqual(e.cacheRead, 1000)
        XCTAssertEqual(e.dedupeKey, "msg_1:req_1")
    }

    func testIgnoresNonAssistantAndGarbage() {
        XCTAssertNil(UsageLineParser.parse(#"{"type":"user","message":{"content":"hi"}}"#))
        XCTAssertNil(UsageLineParser.parse("not json"))
        XCTAssertNil(UsageLineParser.parse(#"{"type":"assistant","timestamp":"2026-08-01T10:00:00Z","message":{"model":"m"}}"#)) // no usage
    }

    func testFoldAggregatesAndDedupes() throws {
        let utc = TimeZone(identifier: "UTC")!
        let e = try XCTUnwrap(UsageLineParser.parse(assistantLine))
        var totals: [DayModelKey: TokenCounts] = [:]
        var seen = Set<String>()
        UsageAggregator.fold(events: [e, e], into: &totals, seen: &seen, timeZone: utc) // duplicate dropped
        let key = DayModelKey(day: "2026-08-01", model: "claude-fable-5")
        XCTAssertEqual(totals[key]?.output, 20)
        XCTAssertEqual(totals[key]?.total, 10 + 20 + 100 + 1000)
        XCTAssertEqual(totals.count, 1)
    }

    func testDayKeyUsesTimeZone() {
        let date = DateParsing.parse("2026-08-01T23:30:00Z")!
        XCTAssertEqual(UsageAggregator.dayKey(for: date, timeZone: TimeZone(identifier: "UTC")!), "2026-08-01")
        XCTAssertEqual(UsageAggregator.dayKey(for: date, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026-08-02")
    }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct UsageEvent: Equatable, Sendable {
    public var timestamp: Date
    public var model: String
    public var dedupeKey: String?
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int
}

public enum UsageLineParser {
    public static func parse(_ line: String) -> UsageEvent? {
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["type"] as? String == "assistant",
              let ts = (root["timestamp"] as? String).flatMap(DateParsing.parse),
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }
        let model = message["model"] as? String ?? "unknown"
        let msgID = message["id"] as? String
        let reqID = root["requestId"] as? String
        let dedupeKey = msgID.map { "\($0):\(reqID ?? "")" }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        return UsageEvent(timestamp: ts, model: model, dedupeKey: dedupeKey,
                          input: count("input_tokens"), output: count("output_tokens"),
                          cacheCreation: count("cache_creation_input_tokens"),
                          cacheRead: count("cache_read_input_tokens"))
    }
}

public struct DayModelKey: Hashable, Sendable {
    public var day: String
    public var model: String
    public init(day: String, model: String) { self.day = day; self.model = model }
}

public struct TokenCounts: Equatable, Sendable {
    public var input = 0, output = 0, cacheCreation = 0, cacheRead = 0
    public init() {}
    public var total: Int { input + output + cacheCreation + cacheRead }
    public mutating func add(_ e: UsageEvent) {
        input += e.input; output += e.output
        cacheCreation += e.cacheCreation; cacheRead += e.cacheRead
    }
}

public enum UsageAggregator {
    public static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func fold(events: [UsageEvent], into totals: inout [DayModelKey: TokenCounts],
                            seen: inout Set<String>, timeZone: TimeZone) {
        for e in events {
            if let key = e.dedupeKey {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            let key = DayModelKey(day: dayKey(for: e.timestamp, timeZone: timeZone), model: e.model)
            totals[key, default: TokenCounts()].add(e)
        }
    }
}
```

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: JSONL usage line parsing and day/model aggregation"`

---

### Task 6: Incremental history scanner

**Files:**
- Create: `Sources/UsageBarCore/UsageHistoryScanner.swift`
- Test: `Tests/UsageBarTests/ScannerTests.swift`

**Interfaces:**
- Consumes: `UsageLineParser`, `UsageAggregator`, `DayModelKey`, `TokenCounts` (Task 5)
- Produces: `final class UsageHistoryScanner { init(root: URL, timeZone: TimeZone = .current); func scan(now: Date = Date()) -> [DayModelKey: TokenCounts] }` — recursive `*.jsonl` scan under `root`, per-file byte-offset cache (append-only files re-read only from the last offset; shrunk files re-read fully), files with mtime older than 8 days skipped, output filtered to the trailing 7 calendar days.

- [ ] **Step 1: Write failing tests (temp-dir fixtures)**

```swift
import XCTest
@testable import UsageBarCore

final class ScannerTests: XCTestCase {
    var dir: URL!
    let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("proj"), withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func line(day: String, model: String = "claude-fable-5", msg: String, out: Int) -> String {
        #"{"type":"assistant","timestamp":"\#(day)T10:00:00Z","requestId":"r","message":{"id":"\#(msg)","model":"\#(model)","usage":{"input_tokens":1,"output_tokens":\#(out),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    }

    func write(_ content: String, to name: String) throws -> URL {
        let url = dir.appendingPathComponent("proj/\(name)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testScansAndFiltersToTrailing7Days() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        _ = try write([line(day: "2026-08-01", msg: "a", out: 5),
                       line(day: "2026-07-20", msg: "b", out: 7)].joined(separator: "\n"),
                      to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)
        let totals = scanner.scan(now: now)
        XCTAssertEqual(totals[DayModelKey(day: "2026-08-01", model: "claude-fable-5")]?.output, 5)
        XCTAssertNil(totals[DayModelKey(day: "2026-07-20", model: "claude-fable-5")]) // outside window
    }

    func testIncrementalAppendOnlyReadsNewLines() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        let url = try write(line(day: "2026-08-01", msg: "a", out: 5) + "\n", to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)
        _ = scanner.scan(now: now)
        // Append a new event and rescan — total should include both, once each.
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data((line(day: "2026-08-01", msg: "b", out: 3) + "\n").utf8))
        try handle.close()
        let totals = scanner.scan(now: now)
        XCTAssertEqual(totals[DayModelKey(day: "2026-08-01", model: "claude-fable-5")]?.output, 8)
    }

    func testRescanWithoutChangesIsStable() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        _ = try write(line(day: "2026-08-01", msg: "a", out: 5), to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)
        let first = scanner.scan(now: now)
        let second = scanner.scan(now: now)
        XCTAssertEqual(first, second)
    }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

```swift
import Foundation

public final class UsageHistoryScanner {
    let root: URL
    let timeZone: TimeZone
    private var offsets: [String: UInt64] = [:]     // path -> bytes consumed
    private var totals: [DayModelKey: TokenCounts] = [:]
    private var seen = Set<String>()

    public init(root: URL, timeZone: TimeZone = .current) {
        self.root = root
        self.timeZone = timeZone
    }

    public func scan(now: Date = Date()) -> [DayModelKey: TokenCounts] {
        let cutoff = now.addingTimeInterval(-8 * 86400)
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys:
            [.contentModificationDateKey, .fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let mtime = values?.contentModificationDate, mtime >= cutoff else { continue }
            let size = UInt64(values?.fileSize ?? 0)
            let path = url.path
            var offset = offsets[path] ?? 0
            if size < offset { offset = 0 }        // truncated/rotated: re-read
            guard size > offset else { continue }  // nothing new
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let events = text.split(separator: "\n").compactMap { UsageLineParser.parse(String($0)) }
            UsageAggregator.fold(events: events, into: &totals, seen: &seen, timeZone: timeZone)
            offsets[path] = size
        }
        // Emit only the trailing 7 calendar days.
        let minDay = UsageAggregator.dayKey(for: now.addingTimeInterval(-6 * 86400), timeZone: timeZone)
        return totals.filter { $0.key.day >= minDay }
    }
}
```

(String comparison works for day filtering because keys are zero-padded `yyyy-MM-dd`.)

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: incremental JSONL history scanner"`

---

### Task 7: Pricing table and cost estimate

**Files:**
- Create: `Sources/UsageBarCore/Pricing.swift`
- Test: `Tests/UsageBarTests/PricingTests.swift`

**Interfaces:**
- Consumes: `TokenCounts`, `DayModelKey` (Task 5)
- Produces: `struct ModelPricing { var inputPerMTok: Double; var outputPerMTok: Double; var cacheWritePerMTok: Double; var cacheReadPerMTok: Double }`
- Produces: `enum Pricing { static func pricing(forModel id: String) -> ModelPricing?; static func cost(_ counts: TokenCounts, model: String) -> Double?; static func totalCost(_ totals: [DayModelKey: TokenCounts]) -> Double }`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import UsageBarCore

final class PricingTests: XCTestCase {
    func testTierMatching() {
        XCTAssertEqual(Pricing.pricing(forModel: "claude-fable-5")?.inputPerMTok, 10)
        XCTAssertEqual(Pricing.pricing(forModel: "claude-opus-5")?.outputPerMTok, 25)
        XCTAssertEqual(Pricing.pricing(forModel: "claude-sonnet-5")?.inputPerMTok, 3)
        XCTAssertEqual(Pricing.pricing(forModel: "claude-haiku-4-5-20251001")?.outputPerMTok, 5)
        XCTAssertNil(Pricing.pricing(forModel: "gpt-5"))
    }

    func testCacheRatesDeriveFromInput() {
        let p = Pricing.pricing(forModel: "claude-fable-5")!
        XCTAssertEqual(p.cacheWritePerMTok, 12.5, accuracy: 0.001)  // 1.25 × 10
        XCTAssertEqual(p.cacheReadPerMTok, 1.0, accuracy: 0.001)    // 0.1 × 10
    }

    func testCostMath() {
        var c = TokenCounts()
        c.input = 1_000_000; c.output = 100_000; c.cacheCreation = 2_000_000; c.cacheRead = 10_000_000
        // fable: 1M×$10 + 0.1M×$50 + 2M×$12.5 + 10M×$1 = 10 + 5 + 25 + 10 = 50
        XCTAssertEqual(Pricing.cost(c, model: "claude-fable-5")!, 50.0, accuracy: 0.01)
        XCTAssertNil(Pricing.cost(c, model: "unknown-model"))
    }

    func testTotalCostSkipsUnknownModels() {
        var c = TokenCounts(); c.output = 1_000_000
        let totals = [
            DayModelKey(day: "2026-08-01", model: "claude-fable-5"): c,   // $50
            DayModelKey(day: "2026-08-01", model: "mystery"): c,          // skipped
        ]
        XCTAssertEqual(Pricing.totalCost(totals), 50.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct ModelPricing: Sendable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double
    public var cacheWritePerMTok: Double { inputPerMTok * 1.25 }
    public var cacheReadPerMTok: Double { inputPerMTok * 0.1 }
}

public enum Pricing {
    // Substring tier match, checked in order (fable/mythos before opus etc.).
    static let tiers: [(needle: String, pricing: ModelPricing)] = [
        ("fable", ModelPricing(inputPerMTok: 10, outputPerMTok: 50)),
        ("mythos", ModelPricing(inputPerMTok: 10, outputPerMTok: 50)),
        ("opus", ModelPricing(inputPerMTok: 5, outputPerMTok: 25)),
        ("sonnet", ModelPricing(inputPerMTok: 3, outputPerMTok: 15)),
        ("haiku", ModelPricing(inputPerMTok: 1, outputPerMTok: 5)),
    ]

    public static func pricing(forModel id: String) -> ModelPricing? {
        guard id.hasPrefix("claude") else { return nil }
        return tiers.first { id.contains($0.needle) }?.pricing
    }

    public static func cost(_ c: TokenCounts, model: String) -> Double? {
        guard let p = pricing(forModel: model) else { return nil }
        let m = 1_000_000.0
        return Double(c.input) / m * p.inputPerMTok
             + Double(c.output) / m * p.outputPerMTok
             + Double(c.cacheCreation) / m * p.cacheWritePerMTok
             + Double(c.cacheRead) / m * p.cacheReadPerMTok
    }

    public static func totalCost(_ totals: [DayModelKey: TokenCounts]) -> Double {
        totals.reduce(0) { sum, entry in
            sum + (cost(entry.value, model: entry.key.model) ?? 0)
        }
    }
}
```

Note the computed cache rates require `ModelPricing` init with just input/output — adjust the struct: declare `cacheWritePerMTok`/`cacheReadPerMTok` as computed properties (as shown), so the memberwise init takes only the two stored values.

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: pricing table and cost estimation"`

---

### Task 8: Refresh policy + directory watcher

**Files:**
- Create: `Sources/UsageBarCore/RefreshPolicy.swift`
- Create: `Sources/UsageBarCore/DirectoryWatcher.swift`
- Test: `Tests/UsageBarTests/RefreshPolicyTests.swift`

**Interfaces:**
- Produces: `enum RefreshPolicy { static let activeInterval: TimeInterval = 10; static let idleInterval: TimeInterval = 60; static func interval(lastActivity: Date?, maxPercent: Double, now: Date) -> TimeInterval }` — active (10s) if activity within last 300s OR maxPercent ≥ 70, else idle (60s).
- Produces: `final class DirectoryWatcher { init?(url: URL, debounce: TimeInterval = 2, onChange: @escaping () -> Void); func stop() }` — FSEvents-based recursive watcher, debounced, callbacks on the main queue. Not unit-tested (thin C-API glue; verified by running the app).

- [ ] **Step 1: Write failing tests for RefreshPolicy**

```swift
import XCTest
@testable import UsageBarCore

final class RefreshPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testActiveWhenRecentActivity() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-60),
                                              maxPercent: 10, now: now), 10)
    }
    func testActiveWhenNearLimit() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 88, now: now), 10)
    }
    func testIdleOtherwise() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-600),
                                              maxPercent: 10, now: now), 60)
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 0, now: now), 60)
    }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement RefreshPolicy**

```swift
import Foundation

public enum RefreshPolicy {
    public static let activeInterval: TimeInterval = 10
    public static let idleInterval: TimeInterval = 60
    public static let activityWindow: TimeInterval = 300

    public static func interval(lastActivity: Date?, maxPercent: Double, now: Date) -> TimeInterval {
        if let last = lastActivity, now.timeIntervalSince(last) < activityWindow {
            return activeInterval
        }
        return maxPercent >= 70 ? activeInterval : idleInterval
    }
}
```

- [ ] **Step 4: Implement DirectoryWatcher (no test — verified in Task 9 by running)**

```swift
import Foundation
import CoreServices

public final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let debounce: TimeInterval
    private var pending = false

    public init?(url: URL, debounce: TimeInterval = 2, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounce = debounce
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.fire()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context,
            [url.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    private func fire() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce) { [weak self] in
            self?.pending = false
            self?.onChange()
        }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 5: Run tests** — Expected: PASS (`swift build` must also succeed).

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: adaptive refresh policy and FSEvents directory watcher"`

---

### Task 9: App wiring — state, status item, main entry

**Files:**
- Create: `Sources/UsageBar/AppState.swift`
- Create: `Sources/UsageBar/StatusItemController.swift`
- Modify: `Sources/UsageBar/main.swift` (replace placeholder)

**Interfaces:**
- Consumes: everything from `UsageBarCore`.
- Produces: `@MainActor final class AppState: ObservableObject` with `@Published var windows: [LimitWindow]`, `@Published var history: [DayModelKey: TokenCounts]`, `@Published var lastUpdated: Date?`, `@Published var errorHint: String?`, plus `func start()`, `func refreshNow()`. Task 10's panel view consumes exactly these.
- Produces: `@MainActor final class StatusItemController` — owns `NSStatusItem` + `NSPopover`; `init(state: AppState, panel: NSViewController)`; observes `state.$windows` via Combine and re-renders the bar title.

- [ ] **Step 1: Implement AppState**

```swift
import Foundation
import Combine
import UsageBarCore

@MainActor
final class AppState: ObservableObject {
    @Published var windows: [LimitWindow] = []
    @Published var history: [DayModelKey: TokenCounts] = [:]
    @Published var lastUpdated: Date?
    @Published var errorHint: String?

    private let client: ClaudeUsageClient
    private let scanner: UsageHistoryScanner
    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var lastActivity: Date?
    private var lastHistoryScan = Date.distantPast

    init() {
        let store = CredentialStore()
        client = ClaudeUsageClient { try store.readToken() }
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        scanner = UsageHistoryScanner(root: projectsDir)

        watcher = DirectoryWatcher(url: projectsDir) { [weak self] in
            self?.lastActivity = Date()
            self?.refreshNow()
        }
    }

    func start() {
        refreshNow()
        scheduleNextPoll()
    }

    func refreshNow() {
        Task { await refresh() }
    }

    private func refresh() async {
        do {
            windows = try await client.fetchUsage()
            lastUpdated = Date()
            errorHint = nil
        } catch UsageClientError.unauthorized {
            errorHint = "Login expired — run `claude` once to refresh it."
        } catch CredentialStore.CredentialError.notFound {
            errorHint = "No Claude Code credentials found. Log in with `claude` first."
        } catch {
            errorHint = "Offline — showing last known data."
        }
        rescanHistoryIfDue()
    }

    func rescanHistoryIfDue(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastHistoryScan) > 300 else { return }
        lastHistoryScan = Date()
        history = scanner.scan()
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        let interval = RefreshPolicy.interval(
            lastActivity: lastActivity,
            maxPercent: windows.map(\.percent).max() ?? 0,
            now: Date())
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
                self?.scheduleNextPoll()
            }
        }
    }
}
```

- [ ] **Step 2: Implement StatusItemController**

```swift
import AppKit
import Combine
import UsageBarCore

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private let state: AppState

    init(state: AppState, panel: NSViewController) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.contentViewController = panel
        popover.behavior = .transient

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        state.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in self?.render(windows) }
            .store(in: &cancellables)
        render(state.windows)
    }

    private func render(_ windows: [LimitWindow]) {
        let text = "✳ " + Formatting.barText(windows)
        let color: NSColor = switch Formatting.severity(windows) {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
        statusItem.button?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: color,
                         .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            state.refreshNow()
            state.rescanHistoryIfDue(force: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
```

- [ ] **Step 3: Replace main.swift**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState!
    var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        let panel = NSHostingController(rootView: UsagePanelView(state: state))
        statusController = StatusItemController(state: state, panel: panel)
        state.start()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon when run outside a bundle
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

For this task only, add a temporary minimal `UsagePanelView` in `main.swift` so it compiles (replaced in Task 10):

```swift
struct UsagePanelView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Text(state.errorHint ?? "\(state.windows.count) windows loaded")
            .padding().frame(width: 300)
    }
}
```

- [ ] **Step 4: Build and run manually**

Run: `swift build && swift test 2>&1 | tail -3` — Expected: build + tests pass.
Then: `swift run UsageBar` (leave running ~30s).
Expected: a menu-bar item appears showing real percentages like `✳ 5h 88% · wk 75% · F 81%`; macOS shows a Keychain permission prompt on first run (click Always Allow); clicking the item opens the placeholder popover. Ctrl-C to quit.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: menu bar app wiring with live quota display"`

---

### Task 10: Panel UI, launch-at-login, app bundle

**Files:**
- Create: `Sources/UsageBar/UsagePanelView.swift` (move out of main.swift, full version)
- Modify: `Sources/UsageBar/main.swift` (remove temporary view)
- Create: `Makefile`
- Create: `README.md`

**Interfaces:**
- Consumes: `AppState` (Task 9), `Formatting`, `Pricing`, `DayModelKey`, `TokenCounts`.

- [ ] **Step 1: Implement the full panel**

```swift
import SwiftUI
import Charts
import ServiceManagement
import UsageBarCore

struct UsagePanelView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Usage").font(.headline)

            if let hint = state.errorHint {
                Label(hint, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            // Gauges with live countdowns (TimelineView ticks every second)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 10) {
                    ForEach(Formatting.sorted(state.windows), id: \.kind) { w in
                        GaugeRow(window: w, now: context.date)
                    }
                }
            }

            Divider()

            Text("Past 7 days").font(.subheadline).bold()
            WeekChart(history: state.history)
            HStack {
                Text("≈ $\(Pricing.totalCost(state.history), specifier: "%.2f") at API prices")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let updated = state.lastUpdated {
                    Text("updated \(updated, style: .relative) ago")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Divider()
            HStack {
                LaunchAtLoginToggle()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct GaugeRow: View {
    let window: LimitWindow
    let now: Date

    var name: String {
        switch window.kind {
        case "session": return "Session (5h)"
        case "weekly_all": return "Weekly · all models"
        case "weekly_scoped": return "Weekly · \(window.modelName ?? "model")"
        default: return window.kind
        }
    }

    var color: Color {
        window.percent >= 90 ? .red : window.percent >= 75 ? .orange : .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.caption)
                Spacer()
                Text("\(Int(window.percent.rounded()))%").font(.caption).bold()
            }
            ProgressView(value: min(window.percent, 100), total: 100)
                .tint(color)
            if let resets = window.resetsAt {
                Text(Formatting.countdown(until: resets, now: now))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct WeekChart: View {
    let history: [DayModelKey: TokenCounts]

    struct Bar: Identifiable {
        var id: String { day + model }
        let day: String     // "08-01" short label
        let model: String   // short model name
        let tokens: Int
    }

    var bars: [Bar] {
        history.map { key, counts in
            Bar(day: String(key.day.suffix(5)),
                model: shortModel(key.model),
                tokens: counts.total)
        }
        .sorted { $0.day < $1.day }
    }

    func shortModel(_ id: String) -> String {
        for name in ["fable", "mythos", "opus", "sonnet", "haiku"] where id.contains(name) {
            return name
        }
        return "other"
    }

    var body: some View {
        if bars.isEmpty {
            Text("No local usage logs found.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(height: 100)
        } else {
            Chart(bars) { bar in
                BarMark(x: .value("Day", bar.day),
                        y: .value("Tokens", bar.tokens))
                    .foregroundStyle(by: .value("Model", bar.model))
            }
            .chartLegend(position: .bottom, spacing: 4)
            .frame(height: 120)
        }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("Launch at login", isOn: $enabled)
            .font(.caption)
            .toggleStyle(.checkbox)
            .onChange(of: enabled) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    error = nil
                } catch {
                    self.error = "Only works from UsageBar.app"
                    enabled = false
                }
            }
            .help(error ?? "Start UsageBar automatically (requires running from UsageBar.app)")
    }
}
```

- [ ] **Step 2: Build, test, and run manually**

Run: `swift build && swift test 2>&1 | tail -3`, then `swift run UsageBar`.
Expected: clicking the bar item shows three gauges with ticking countdowns, a stacked bar chart of the past week, and a plausible cost line. The launch-at-login toggle shows its "requires bundle" help when run via `swift run` (expected).

- [ ] **Step 3: Write the Makefile**

```makefile
APP := UsageBar.app
BINARY := .build/release/UsageBar

.PHONY: app clean install test

test:
	swift test

$(BINARY): $(shell find Sources -name '*.swift') Package.swift
	swift build -c release

app: $(BINARY)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/UsageBar
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>CFBundleIdentifier</key><string>com.jeff613.usagebar</string>' \
	  '  <key>CFBundleName</key><string>UsageBar</string>' \
	  '  <key>CFBundleExecutable</key><string>UsageBar</string>' \
	  '  <key>CFBundlePackageType</key><string>APPL</string>' \
	  '  <key>CFBundleShortVersionString</key><string>1.0</string>' \
	  '  <key>LSMinimumSystemVersion</key><string>14.0</string>' \
	  '  <key>LSUIElement</key><true/>' \
	  '</dict></plist>' > $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)
	@echo "Built $(APP) — copy to /Applications and open it."

install: app
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/
	open /Applications/$(APP)

clean:
	rm -rf .build $(APP)
```

Add `UsageBar.app/` and `.build/` to `.gitignore`.

- [ ] **Step 4: Build the bundle and verify end-to-end**

Run: `make app && open UsageBar.app`
Expected: app launches with no Dock icon, menu-bar item shows live data, Keychain prompt appears once for the bundled app (Always Allow), popover works, launch-at-login toggle now succeeds. Quit via the panel's Quit button.

- [ ] **Step 5: Write README.md** — brief: what it is, `make install`, the Keychain prompt note, `make test`, and that Codex/OpenAI support is a planned follow-up via the same architecture (new client + windows merged into `AppState.windows`).

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: usage panel UI, launch at login, app bundle"`

---

## Verification checklist (end of plan)

- [ ] `swift test` — all green.
- [ ] `make app && open UsageBar.app` — bar shows live percentages matching `claude` `/usage`.
- [ ] While running a Claude Code prompt, the bar percentage updates within ~10s of activity.
- [ ] Panel: gauges + countdowns tick, 7-day chart populated, cost line plausible.
- [ ] Kill network (Wi-Fi off) → bar keeps last data, panel shows offline hint.
