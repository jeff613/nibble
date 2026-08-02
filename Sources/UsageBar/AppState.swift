import Foundation
import Combine
import UsageBarCore

@MainActor
final class AppState: ObservableObject {
    /// Set once the user has explicitly connected. The token itself is never
    /// copied — only this flag is persisted, and the credential is read live.
    private static let consentKey = "hasConnectedClaudeCodeLogin"

    @Published var windows: [LimitWindow] = []
    @Published var history: [DayModelKey: TokenCounts] = [:]
    @Published var lastUpdated: Date?
    @Published var errorHint: String?
    @Published var needsSetup: Bool

    private let credentials = ClaudeCodeCredentials()
    private let defaults: UserDefaults
    private let client: ClaudeUsageClient
    private let scanner: UsageHistoryScanner
    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var lastActivity: Date?
    private var lastHistoryScan = Date.distantPast
    private var lastFetch: Date?
    private var backoffUntil: Date?
    private var consecutiveRateLimits = 0
    private var inFlight = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let credentials = self.credentials
        client = ClaudeUsageClient { try? credentials.readToken() }
        needsSetup = !defaults.bool(forKey: Self.consentKey)

        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        scanner = UsageHistoryScanner(root: projectsDir)

        // Any write under ~/.claude/projects means Claude Code is active — refresh now.
        watcher = DirectoryWatcher(url: projectsDir) { [weak self] in
            Task { @MainActor in
                self?.lastActivity = Date()
                self?.refreshNow()
            }
        }
    }

    func start() {
        refreshNow()
        scheduleNextPoll()
    }

    /// Requests a refresh. Coalesced: ignored while a request is in flight,
    /// inside the minimum spacing window, or while backing off from a 429.
    func refreshNow(force: Bool = false) {
        guard !needsSetup, !inFlight else { return }
        let now = Date()
        if !force {
            if let backoffUntil, now < backoffUntil { return }
            guard RefreshPolicy.shouldFetch(lastFetch: lastFetch, now: now) else { return }
        }
        Task { await refresh() }
    }

    /// Reads the Claude Code login for the first time and confirms it works
    /// before remembering the user's consent. Returns an error message, or nil.
    func connect() async -> String? {
        do {
            _ = try credentials.readToken()
        } catch let error as ClaudeCodeCredentials.LookupError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }

        do {
            lastFetch = Date()
            windows = try await client.fetchUsage()
            defaults.set(true, forKey: Self.consentKey)
            needsSetup = false
            lastUpdated = Date()
            errorHint = nil
            rescanHistoryIfDue(force: true)
            scheduleNextPoll()
            return nil
        } catch UsageClientError.unauthorized {
            return "Claude rejected that login. Run `claude` and sign in again."
        } catch UsageClientError.rateLimited {
            return "Anthropic is rate limiting this Mac right now. Wait a minute and try again."
        } catch UsageClientError.badStatus(let code) {
            return "Anthropic returned HTTP \(code)."
        } catch {
            return "Couldn't reach Anthropic. Check your connection."
        }
    }

    func disconnect() {
        defaults.set(false, forKey: Self.consentKey)
        windows = []
        lastUpdated = nil
        errorHint = nil
        needsSetup = true
        timer?.invalidate()
    }

    private func refresh() async {
        inFlight = true
        lastFetch = Date()
        defer { inFlight = false }

        do {
            windows = try await client.fetchUsage()
            lastUpdated = Date()
            errorHint = nil
            backoffUntil = nil
            consecutiveRateLimits = 0
        } catch UsageClientError.notConfigured {
            errorHint = "Can't read the Claude Code login — is it still signed in?"
        } catch UsageClientError.unauthorized {
            errorHint = "Login expired — run `claude` and sign in again."
        } catch UsageClientError.rateLimited(let retryAfter) {
            consecutiveRateLimits += 1
            let wait = RefreshPolicy.backoff(
                consecutiveRateLimits: consecutiveRateLimits, retryAfter: retryAfter)
            backoffUntil = Date().addingTimeInterval(wait)
            errorHint = "Rate limited by Anthropic — retrying in \(Int(wait / 60) > 0 ? "\(Int(wait / 60))m" : "\(Int(wait))s")."
        } catch UsageClientError.badStatus(let code) {
            errorHint = "Anthropic returned HTTP \(code) — showing last known data."
        } catch let error as URLError where error.code == .notConnectedToInternet {
            errorHint = "No internet connection — showing last known data."
        } catch {
            errorHint = "Couldn't reach Anthropic — showing last known data."
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
