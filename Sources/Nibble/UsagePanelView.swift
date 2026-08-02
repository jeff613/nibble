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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Nibble").font(.headline)

            Text("Nibble reads the Claude login already stored on this Mac by Claude Code. macOS will ask you to approve — nothing is read until you do.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("The token is read fresh on each check and never copied elsewhere. Your quota data goes nowhere but this window.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(connecting ? "Connecting…" : "Use my Claude Code login") { connect() }
                .keyboardShortcut(.defaultAction)
                .disabled(connecting)
                .frame(maxWidth: .infinity)

            HStack {
                Text("Requires Claude Code, signed in.")
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
            error = await state.connect()
            connecting = false
        }
    }
}

// MARK: - Main panel

struct DashboardView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Usage").font(.headline)

            if let hint = state.errorHint {
                Label(hint, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Countdowns tick every second regardless of polling.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    if let until = state.backoffUntil, until > context.date {
                        Label(
                            "Rate limited by Anthropic — resuming in \(Formatting.duration(until.timeIntervalSince(context.date))). Numbers below may be stale.",
                            systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Formatting.sorted(state.windows), id: \.kind) { window in
                        GaugeRow(window: window, now: context.date)
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
                Menu {
                    Button("Disconnect") { state.disconnect() }
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

    var bars: [Bar] {
        history
            .map { key, counts in
                Bar(day: String(key.day.suffix(5)),
                    model: ModelPalette.family(for: key.model),
                    tokens: counts.total)
            }
            .sorted { $0.day < $1.day }
    }

    /// Only the families on screen, in canonical order — colours come from the
    /// fixed palette, never from the chart's positional defaults.
    var scale: (domain: [String], range: [Color]) {
        let domain = ModelPalette.presentFamilies(in: history.keys.map(\.model))
        return (domain, domain.map { Color(hex: ModelPalette.hex(for: $0)) })
    }

    var body: some View {
        if bars.isEmpty {
            Text("No local Claude Code logs found in ~/.claude/projects.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 100)
        } else {
            Chart(bars) { bar in
                BarMark(x: .value("Day", bar.day),
                        y: .value("Tokens", bar.tokens))
                    .foregroundStyle(by: .value("Model", bar.model))
            }
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
