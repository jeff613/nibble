import SwiftUI
import Charts
import ServiceManagement
import NibbleCore

struct UsagePanelView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            if state.needsSetup {
                SetupView(state: state)
            } else {
                DashboardView(state: state)
            }
        }
        .frame(width: 340)
    }
}

// MARK: - First run

struct SetupView: View {
    @ObservedObject var state: AppState
    @State private var error: String?
    @State private var connecting = false

    var hidden: [Provider] {
        Provider.allCases.filter { state.isHidden($0) && state.loginPresent($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Nibble").font(.headline)

            Text("Nibble looks for Claude Code, Codex, and Grok logins already stored on this Mac. Tokens are read live and never copied elsewhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Quota data goes nowhere but this window.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(connecting ? "Looking…" : "Look for CLI logins") { connect() }
                .keyboardShortcut(.defaultAction)
                .disabled(connecting)
                .frame(maxWidth: .infinity)

            ForEach(hidden, id: \.self) { provider in
                Button("Show \(provider.displayName)") { state.show(provider) }
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Text("Requires claude, codex, or grok, signed in.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        error = nil
        Task {
            error = await state.lookForLogins()
            connecting = false
        }
    }
}

// MARK: - Main panel

struct DashboardView: View {
    @ObservedObject var state: AppState

    var connected: [Provider] {
        Provider.allCases.filter { state.connected.contains($0) }
    }

    var hidden: [Provider] {
        Provider.allCases.filter { state.isHidden($0) && state.loginPresent($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Usage").font(.headline)

            // Countdowns tick every second regardless of polling.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(connected, id: \.self) { provider in
                        providerSection(provider, now: context.date)
                    }
                }
            }

            Divider()

            Text("Past 7 days").font(.subheadline).bold()
            WeekChart(history: state.history)

            HStack {
                Text("≈ $\(Pricing.totalCost(state.history), specifier: "%.2f") at API prices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let updated = state.lastUpdated {
                    Text("updated \(updated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack {
                LaunchAtLoginToggle()
                Spacer()
                Picker("Menu bar", selection: $state.selectedBarProvider) {
                    ForEach(connected, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Menu {
                    ForEach(connected, id: \.self) { provider in
                        Button("Hide \(provider.displayName)") { state.disconnect(provider) }
                    }
                    ForEach(hidden, id: \.self) { provider in
                        Button("Show \(provider.displayName)") { state.show(provider) }
                    }
                    Button("Quit Nibble") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func providerSection(_ provider: Provider, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(provider.displayName).font(.subheadline).bold()
            if let until = state.backoff[provider], until > now {
                Label(
                    "Rate limited, resuming in \(Formatting.duration(until.timeIntervalSince(now))). Numbers below may be stale.",
                    systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hint = state.hints[provider] {
                Label(hint, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Formatting.sorted(state.windowsByProvider[provider] ?? []), id: \.kind) { window in
                GaugeRow(window: window, now: now)
            }
        }
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
        case "weekly": return "Weekly"
        case "monthly": return "Monthly"
        case "credits": return "Credits"
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WeekChart: View {
    let history: [DayModelKey: TokenCounts]

    struct Bar: Identifiable {
        var id: String { day + model }
        let day: String
        let model: String
        let tokens: Int
    }

    var days: [String] {
        UsageAggregator.lastSevenDays(endingOn: Date(), timeZone: .current)
    }

    var bars: [Bar] {
        UsageAggregator.dayFamilyTotals(history, days: days).map {
            Bar(day: String($0.day.suffix(5)), model: $0.family, tokens: $0.tokens)
        }
    }

    /// Only the families on screen, in canonical order — colours come from the
    /// fixed palette, never from the chart's positional defaults.
    var scale: (domain: [String], range: [Color]) {
        let domain = ModelPalette.present(in: history.keys.map(\.model))
        return (domain, domain.map { Color(hex: ModelPalette.hex(for: $0)) })
    }

    var body: some View {
        if bars.isEmpty {
            Text("No local usage logs found for the visible providers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 100)
        } else {
            Chart(bars) { bar in
                BarMark(x: .value("Day", bar.day),
                        y: .value("Tokens", bar.tokens))
                    .foregroundStyle(by: .value("Model", bar.model))
            }
            .chartXScale(domain: days.map { String($0.suffix(5)) })
            .chartForegroundStyleScale(domain: scale.domain, range: scale.range)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Double.self) {
                            Text(Formatting.compactCount(tokens))
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 4)
            .frame(height: 120)
        }
    }
}

extension Color {
    /// Builds a colour from a 6-digit RGB hex, as stored in `ModelPalette`.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var failed = false

    var body: some View {
        Toggle("Launch at login", isOn: $enabled)
            .font(.caption)
            .toggleStyle(.checkbox)
            .onChange(of: enabled) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    failed = false
                } catch {
                    failed = true
                    enabled = false
                }
            }
            .help(failed
                  ? "Only works when running from Nibble.app"
                  : "Start Nibble automatically at login")
    }
}
