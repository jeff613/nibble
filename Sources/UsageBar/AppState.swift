import Foundation
import Combine
import UsageBarCore

@MainActor
final class AppState: ObservableObject {
    @Published var windows: [LimitWindow] = []
    @Published var history: [DayModelKey: TokenCounts] = [:]
    @Published var lastUpdated: Date?
    @Published var errorHint: String?
    /// True until the user has connected a working token.
    @Published var needsSetup: Bool

    private let tokenStore = TokenStore()
    private let client: ClaudeUsageClient
    private let scanner: UsageHistoryScanner
    private var watcher: DirectoryWatcher?
    private var timer: Timer?
    private var lastActivity: Date?
    private var lastHistoryScan = Date.distantPast

    init() {
        let store = tokenStore
        client = ClaudeUsageClient { store.load() }
        needsSetup = store.load() == nil

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

    func refreshNow() {
        guard !needsSetup else { return }
        Task { await refresh() }
    }

    /// Verifies a pasted token against the live endpoint before storing it.
    func connect(token: String) async -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Paste the token first." }
        do {
            windows = try await client.validate(token: trimmed)
            try tokenStore.save(trimmed)
            needsSetup = false
            lastUpdated = Date()
            errorHint = nil
            rescanHistoryIfDue(force: true)
            scheduleNextPoll()
            return nil
        } catch UsageClientError.unauthorized {
            return "That token was rejected. Generate a fresh one with `claude setup-token`."
        } catch UsageClientError.badStatus(let code) {
            return "Anthropic returned HTTP \(code). Try again in a moment."
        } catch let error as TokenStore.TokenError {
            return error.errorDescription
        } catch {
            return "Couldn't reach Anthropic. Check your connection."
        }
    }

    func signOut() {
        try? tokenStore.delete()
        windows = []
        lastUpdated = nil
        errorHint = nil
        needsSetup = true
        timer?.invalidate()
    }

    private func refresh() async {
        do {
            windows = try await client.fetchUsage()
            lastUpdated = Date()
            errorHint = nil
        } catch UsageClientError.notConfigured {
            needsSetup = true
        } catch UsageClientError.unauthorized {
            errorHint = "Token expired or revoked — reconnect with a new `claude setup-token`."
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
