import Foundation
import Combine
import UsageBarCore

@MainActor
final class AppState: ObservableObject {
    /// Set once the user has explicitly connected. The token itself is never
    /// copied — only this flag is persisted, and the credential is read live.
    private static let consentKey = "hasConnectedClaudeCodeLogin"
    /// Persisted so quitting and relaunching during a penalty doesn't re-trip it.
    private static let backoffKey = "rateLimitBackoffUntil"

    @Published var windows: [LimitWindow] = []
    @Published var history: [DayModelKey: TokenCounts] = [:]
    @Published var lastUpdated: Date?
    @Published var errorHint: String?
    @Published var needsSetup: Bool
    /// Non-nil while rate limited; the panel renders a live countdown to it.
    @Published var backoffUntil: Date?

    private let credentials = ClaudeCodeCredentials()
    private let defaults: UserDefaults
    private let client: ClaudeUsageClient
    private let scanner: UsageHistoryScanner
    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var lastActivity: Date?
    private var lastHistoryScan = Date.distantPast
    private var lastFetch: Date?
    private var consecutiveRateLimits = 0
    private var inFlight = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let credentials = self.credentials
        client = ClaudeUsageClient { try? credentials.readToken() }
        needsSetup = !defaults.bool(forKey: Self.consentKey)

        // Resume any penalty that was still running when we last quit.
        if let stored = defaults.object(forKey: Self.backoffKey) as? Date, stored > Date() {
            backoffUntil = stored
        } else {
            defaults.removeObject(forKey: Self.backoffKey)
        }

        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        scanner = UsageHistoryScanner(root: projectsDir)

        // Quota only moves when tokens are actually spent, so a write alone
        // isn't enough — only refresh when the scan finds new usage events.
        watcher = DirectoryWatcher(url: projectsDir) { [weak self] in
            Task { @MainActor in
                guard let self, self.scanHistory() > 0 else { return }
                self.lastActivity = Date()
                self.refreshNow()
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
            defaults.removeObject(forKey: Self.backoffKey)
            // Reset times just changed; re-aim the timer at the next one.
            scheduleNextPoll()
        } catch UsageClientError.notConfigured {
            errorHint = "Can't read the Claude Code login — is it still signed in?"
        } catch UsageClientError.unauthorized {
            errorHint = "Login expired — run `claude` and sign in again."
        } catch UsageClientError.rateLimited(let retryAfter) {
            consecutiveRateLimits += 1
            let wait = RefreshPolicy.backoff(
                consecutiveRateLimits: consecutiveRateLimits, retryAfter: retryAfter)
            let until = Date().addingTimeInterval(wait)
            backoffUntil = until
            defaults.set(until, forKey: Self.backoffKey)
            errorHint = nil  // the panel shows a live countdown instead
            scheduleWakeUp(after: wait)
        } catch UsageClientError.badStatus(let code) {
            errorHint = "Anthropic returned HTTP \(code) — showing last known data."
        } catch let error as URLError where error.code == .notConnectedToInternet {
            errorHint = "No internet connection — showing last known data."
        } catch {
            errorHint = "Couldn't reach Anthropic — showing last known data."
        }
        rescanHistoryIfDue()
    }

    /// Incremental — only reads bytes appended since the last scan, so it's
    /// cheap enough to run on every file-system event. Returns new event count.
    @discardableResult
    func scanHistory() -> Int {
        lastHistoryScan = Date()
        history = scanner.scan()
        return scanner.newEventsInLastScan
    }

    func rescanHistoryIfDue(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastHistoryScan) > 300 else { return }
        scanHistory()
    }

    /// Sleeps until the penalty expires, rather than waking to be refused again.
    private func scheduleWakeUp(after seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds + 1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
                self?.scheduleNextPoll()
            }
        }
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        if let backoffUntil, backoffUntil > Date() {
            return scheduleWakeUp(after: backoffUntil.timeIntervalSinceNow)
        }
        let interval = RefreshPolicy.nextWakeUp(
            lastActivity: lastActivity,
            resets: windows.compactMap(\.resetsAt),
            now: Date())
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
                self?.scheduleNextPoll()
            }
        }
    }
}
