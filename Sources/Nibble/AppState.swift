import Foundation
import Combine
import NibbleCore

@MainActor
final class AppState: ObservableObject {
    private static let selectedKey = "selectedBarProvider"
    private static func backoffKey(_ p: Provider) -> String {
        p == .claude ? "rateLimitBackoffUntil" : "rateLimitBackoffUntil.\(p.rawValue)"
    }

    @Published var windowsByProvider: [Provider: [LimitWindow]] = [:]
    /// Windows for the selected bar provider, so existing views keep compiling.
    @Published var windows: [LimitWindow] = []
    @Published var history: [DayModelKey: TokenCounts] = [:]
    @Published var lastUpdated: Date?
    @Published var errorHint: String?
    @Published var hints: [Provider: String] = [:]
    @Published var needsSetup: Bool
    @Published private(set) var connected: Set<Provider> = []
    @Published var selectedBarProvider: Provider = .claude {
        didSet {
            defaults.set(selectedBarProvider.rawValue, forKey: Self.selectedKey)
            publishBar()
        }
    }
    /// Rate-limit expiry per provider.
    @Published var backoff: [Provider: Date] = [:]
    /// Selected provider's backoff, for the existing panel caption.
    @Published var backoffUntil: Date?
    @Published private(set) var accessDenied = false

    private let defaults: UserDefaults
    private let claudeCredentials = ClaudeCodeCredentials()
    private let claudeClient: ClaudeUsageClient
    private let claudeScanner: UsageHistoryScanner
    private let codexClient: CodexUsageClient
    private let codexScanner: CodexHistoryScanner
    private let grokClient: GrokUsageClient
    private let grokScanner: GrokHistoryScanner
    private var watchers: [Provider: DirectoryWatcher] = [:]
    private var timer: Timer?
    private var lastActivity: [Provider: Date] = [:]
    private var lastHistoryScan: [Provider: Date] = [:]
    private var lastFetch: [Provider: Date] = [:]
    private var consecutiveRateLimits: [Provider: Int] = [:]
    private var inFlight: Set<Provider> = []
    private var historyByProvider: [Provider: [DayModelKey: TokenCounts]] = [:]

    func loginPresent(_ provider: Provider) -> Bool { canRead(provider) }
    func isHidden(_ provider: Provider) -> Bool { isOptedOut(provider) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        needsSetup = true
        let claudeCredentials = self.claudeCredentials
        claudeClient = ClaudeUsageClient { try claudeCredentials.readToken(reload: $0) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeScanner = UsageHistoryScanner(root: home.appendingPathComponent(".claude/projects"))
        codexClient = CodexUsageClient { reload in
            // File credentials have no rotation; reload is a fresh read.
            _ = reload
            return try CodexCredentials().readToken()
        }
        codexScanner = CodexHistoryScanner(root: home.appendingPathComponent(".codex/sessions"))
        grokClient = GrokUsageClient { reload in
            _ = reload
            return try GrokCredentials().readToken()
        }
        grokScanner = GrokHistoryScanner(root: home.appendingPathComponent(".grok/sessions"))

        if let raw = defaults.string(forKey: Self.selectedKey),
           let stored = Provider(rawValue: raw) {
            selectedBarProvider = stored
        }

        for p in Provider.allCases {
            if let stored = defaults.object(forKey: Self.backoffKey(p)) as? Date, stored > Date() {
                backoff[p] = stored
            } else {
                defaults.removeObject(forKey: Self.backoffKey(p))
            }
        }

        adoptAvailableProviders()
        needsSetup = connected.isEmpty
        installWatchers()
        publishBar()
    }

    func start() {
        for p in connected {
            rescanHistoryIfDue(provider: p, force: true)
            refreshNow(provider: p)
        }
        scheduleNextPoll()
    }

    /// Re-probe local CLI logins. Used by the empty setup screen.
    func lookForLogins() async -> String? {
        adoptAvailableProviders()
        if connected.isEmpty {
            return "No Claude Code, Codex, or Grok login found. Sign in with one of those CLIs, then try again."
        }
        needsSetup = false
        installWatchers()
        for p in connected {
            rescanHistoryIfDue(provider: p, force: true)
            refreshNow(provider: p, force: true)
        }
        publishBar()
        scheduleNextPoll()
        return nil
    }

    func refreshNow(force: Bool = false) {
        for p in connected { refreshNow(provider: p, force: force) }
    }

    func refreshNow(provider: Provider, force: Bool = false) {
        guard connected.contains(provider), !inFlight.contains(provider) else { return }
        if provider == .claude && accessDenied { return }
        let now = Date()
        if !force {
            if let until = backoff[provider], now < until { return }
            guard RefreshPolicy.shouldFetch(lastFetch: lastFetch[provider], now: now) else { return }
        }
        Task { await refresh(provider) }
    }

    func panelOpened() {
        if accessDenied {
            accessDenied = false
            hints[.claude] = nil
            errorHint = nil
            scheduleNextPoll()
        }
        refreshNow()
        for p in connected { rescanHistoryIfDue(provider: p, force: true) }
    }

    /// Hide a provider. Local CLI logins are left alone; Nibble just stops
    /// reading them until `show` is called.
    func disconnect(_ provider: Provider) {
        defaults.set(true, forKey: provider.optOutKey)
        connected.remove(provider)
        windowsByProvider[provider] = nil
        historyByProvider[provider] = nil
        hints[provider] = nil
        backoff[provider] = nil
        defaults.removeObject(forKey: Self.backoffKey(provider))
        rebuildHistory()
        if connected.isEmpty {
            needsSetup = true
            lastUpdated = nil
            errorHint = nil
            timer?.invalidate()
            windows = []
            backoffUntil = nil
            return
        }
        if let next = Provider.fallback(selected: selectedBarProvider, connected: connected),
           next != selectedBarProvider {
            selectedBarProvider = next
        }
        publishBar()
    }

    func show(_ provider: Provider) {
        defaults.set(false, forKey: provider.optOutKey)
        guard canRead(provider) else { return }
        connected.insert(provider)
        needsSetup = false
        installWatchers()
        rescanHistoryIfDue(provider: provider, force: true)
        refreshNow(provider: provider, force: true)
        publishBar()
        scheduleNextPoll()
    }

    private func refresh(_ provider: Provider) async {
        inFlight.insert(provider)
        lastFetch[provider] = Date()
        defer { inFlight.remove(provider) }

        do {
            switch provider {
            case .claude:
                windowsByProvider[.claude] = try await claudeClient.fetchUsage()
            case .codex:
                windowsByProvider[.codex] = try await codexClient.fetchUsage()
            case .grok:
                windowsByProvider[.grok] = try await grokClient.fetchUsage()
            }
            lastUpdated = Date()
            hints[provider] = nil
            if provider == .claude { errorHint = nil }
            backoff[provider] = nil
            consecutiveRateLimits[provider] = 0
            defaults.removeObject(forKey: Self.backoffKey(provider))
            publishBar()
            scheduleNextPoll()
        } catch ClaudeCodeCredentials.LookupError.accessDenied {
            accessDenied = true
            hints[.claude] = ClaudeCodeCredentials.LookupError.accessDenied.errorDescription
            errorHint = hints[.claude]
            timer?.invalidate()
        } catch ClaudeCodeCredentials.LookupError.notSignedIn {
            setHint(provider, "Can't read the Claude Code login — is it still signed in?")
        } catch CodexCredentials.LookupError.notSignedIn {
            setHint(provider, "Can't read the Codex login — is it still signed in?")
        } catch GrokCredentials.LookupError.notSignedIn {
            setHint(provider, "Can't read the Grok login — is it still signed in?")
        } catch UsageClientError.unauthorized {
            setHint(provider, "Login expired — run `\(cliName(provider))` and sign in again.")
        } catch UsageClientError.rateLimited(let retryAfter) {
            let n = (consecutiveRateLimits[provider] ?? 0) + 1
            consecutiveRateLimits[provider] = n
            let wait = RefreshPolicy.backoff(consecutiveRateLimits: n, retryAfter: retryAfter)
            let until = Date().addingTimeInterval(wait)
            backoff[provider] = until
            defaults.set(until, forKey: Self.backoffKey(provider))
            hints[provider] = nil
            publishBar()
            scheduleWakeUp(after: wait)
        } catch UsageClientError.badStatus(let code) {
            setHint(provider, "HTTP \(code) — showing last known data.")
        } catch let error as URLError where error.code == .notConnectedToInternet {
            setHint(provider, "No internet connection — showing last known data.")
        } catch {
            setHint(provider, "Couldn't reach \(provider.displayName) — showing last known data.")
        }
        rescanHistoryIfDue(provider: provider)
    }

    @discardableResult
    func scanHistory(_ provider: Provider) -> Int {
        lastHistoryScan[provider] = Date()
        let n: Int
        switch provider {
        case .claude:
            historyByProvider[.claude] = claudeScanner.scan()
            n = claudeScanner.newEventsInLastScan
        case .codex:
            historyByProvider[.codex] = codexScanner.scan()
            n = codexScanner.newEventsInLastScan
        case .grok:
            historyByProvider[.grok] = grokScanner.scan()
            n = grokScanner.newEventsInLastScan
        }
        rebuildHistory()
        return n
    }

    func rescanHistoryIfDue(provider: Provider, force: Bool = false) {
        let last = lastHistoryScan[provider] ?? .distantPast
        guard force || Date().timeIntervalSince(last) > 300 else { return }
        scanHistory(provider)
    }

    private func rebuildHistory() {
        history = HistoryMerge.union(connected.map { historyByProvider[$0] ?? [:] })
    }

    private func adoptAvailableProviders() {
        var next: Set<Provider> = []
        for p in Provider.allCases where !isOptedOut(p) && canRead(p) {
            next.insert(p)
        }
        connected = next
        if let pick = Provider.fallback(selected: selectedBarProvider, connected: connected),
           pick != selectedBarProvider {
            selectedBarProvider = pick
        }
    }

    private func isOptedOut(_ provider: Provider) -> Bool {
        defaults.bool(forKey: provider.optOutKey)
    }

    private func canRead(_ provider: Provider) -> Bool {
        switch provider {
        case .claude:
            do {
                _ = try claudeCredentials.readToken()
                return true
            } catch ClaudeCodeCredentials.LookupError.accessDenied {
                accessDenied = true
                return false
            } catch {
                return false
            }
        case .codex:
            return (try? CodexCredentials().readToken()) != nil
        case .grok:
            return (try? GrokCredentials().readToken()) != nil
        }
    }

    private func installWatchers() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [Provider: URL] = [
            .claude: home.appendingPathComponent(".claude/projects"),
            .codex: home.appendingPathComponent(".codex/sessions"),
            .grok: home.appendingPathComponent(".grok/sessions"),
        ]
        for (provider, url) in roots where watchers[provider] == nil {
            watchers[provider] = DirectoryWatcher(url: url) { [weak self] in
                Task { @MainActor in
                    guard let self, self.connected.contains(provider) else { return }
                    guard self.scanHistory(provider) > 0 else { return }
                    self.lastActivity[provider] = Date()
                    self.refreshNow(provider: provider)
                }
            }
        }
    }

    private func publishBar() {
        let selected = Provider.fallback(selected: selectedBarProvider, connected: connected) ?? selectedBarProvider
        windows = windowsByProvider[selected] ?? []
        backoffUntil = backoff[selected]
        errorHint = hints[selected]
    }

    private func setHint(_ provider: Provider, _ text: String) {
        hints[provider] = text
        if provider == selectedBarProvider || windows.isEmpty {
            errorHint = text
        }
    }

    private func cliName(_ provider: Provider) -> String {
        switch provider {
        case .claude: return "claude"
        case .codex: return "codex"
        case .grok: return "grok"
        }
    }

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
        if accessDenied && connected == [.claude] { return }
        let now = Date()
        var wait = RefreshPolicy.idleHeartbeat
        var anyReady = false
        for p in connected {
            if p == .claude && accessDenied { continue }
            if let until = backoff[p], until > now {
                wait = min(wait, until.timeIntervalSince(now) + 1)
                continue
            }
            anyReady = true
            let interval = RefreshPolicy.nextWakeUp(
                lastActivity: lastActivity[p],
                resets: (windowsByProvider[p] ?? []).compactMap(\.resetsAt),
                now: now)
            wait = min(wait, interval)
        }
        guard anyReady || wait < RefreshPolicy.idleHeartbeat else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(1, wait), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
                self?.scheduleNextPoll()
            }
        }
    }
}
