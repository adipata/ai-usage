import SwiftUI
import Charts

/// Compact dashboard card: claude.ai plan limits on top, platform.claude.com figures below.
struct ClaudeCard: View {
    let claudeAI: SourceState<ClaudeAIUsage>
    let platform: SourceState<PlatformUsage>
    var onSignIn: (WebSite) -> Void = { _ in }

    static let spendingURL = URL(string: "https://platform.claude.com/spending")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Claude", systemImage: "sparkle", tint: Color(red: 0.85, green: 0.47, blue: 0.34),
                       updatedAt: [claudeAI.fetchedAt, platform.fetchedAt].compactMap { $0 }.min())

            SectionLabel("claude.ai")
            if let usage = claudeAI.value {
                // Ticks every minute so the countdowns stay current without refetching.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 6) {
                        if let weekly = usage.weekly { LimitRow(limit: weekly, now: context.date) }
                        ForEach(usage.modelLimits) { LimitRow(limit: $0, now: context.date) }
                    }
                }
            }
            SourceStatus(state: claudeAI, site: .claudeAI, onSignIn: onSignIn)

            Divider()

            HStack {
                SectionLabel("Platform")
                Spacer()
                Link(destination: Self.spendingURL) {
                    Label("Spending", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .font(.caption2)
            }
            if let usage = platform.value {
                PlatformFigures(usage: usage)
                if let keys = usage.keys, !keys.isEmpty {
                    APIKeyList(keys: keys)
                }
            }
            SourceStatus(state: platform, site: .claudePlatform, onSignIn: onSignIn)
        }
        .providerCard()
    }
}

/// One line: name · bar · % · "Sat 7:00 PM" · countdown.
struct LimitRow: View {
    let limit: UsageLimit
    var now: Date = .now

    var body: some View {
        HStack(spacing: 8) {
            Text(limit.title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            UsageBar(percent: limit.percentUsed)
            Text("\(Int(limit.percentUsed.rounded()))%")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 40, alignment: .trailing)
            Text(limit.resetsAt.map(UsageFormat.resetLabel) ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 64, alignment: .trailing)
            Text(UsageFormat.timeLeft(until: limit.resetsAt, now: now) ?? "")
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 50, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Credits · Spend this month · Tokens (with the 7-day sparkline).
private struct PlatformFigures: View {
    let usage: PlatformUsage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatTile(label: "Credits", value: usage.organizationCredits)
            StatTile(label: "Spend this month", value: usage.spendThisMonth, caption: spendCaption)
            StatTile(label: "Tokens", value: usage.tokenVolume, caption: tokenCaption) {
                if let bars = usage.tokenBars, !bars.isEmpty {
                    TokenSparkline(bars: bars)
                }
            }
        }
    }

    /// "of $60 · 3%"
    private var spendCaption: String? {
        let parts = [
            usage.spendLimit.map { "of \($0)" },
            usage.spendPercent.map { "\(Int($0.rounded()))%" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "7d · ↑136%"
    private var tokenCaption: String? {
        var parts: [String] = []
        if let period = usage.tokenPeriod,
           let days = period.split(separator: " ").compactMap({ Int($0) }).first {
            parts.append("\(days)d")
        }
        if let trend = usage.tokenTrend {
            let words = trend.split(separator: " ")
            if words.count == 2 {
                parts.append((words[0] == "Up" ? "↑" : "↓") + words[1] + "%")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Seven daily bars, oldest first, scaled to the tallest. Shape only: the Console gives no per-day values.
struct TokenSparkline: View {
    let bars: [Double]

    var body: some View {
        let maximum = max(bars.max() ?? 0, 0.0001)
        Chart(Array(bars.enumerated()), id: \.offset) { day in
            BarMark(
                x: .value("Day", day.offset),
                y: .value("Tokens", day.element / maximum)
            )
            .foregroundStyle(.tint)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartLegend(.hidden)
        .frame(width: 48, height: 18)
        .accessibilityLabel("Token volume, last \(bars.count) days")
    }
}

/// "Keys · this month": up to five keys by cost, then "+N more".
private struct APIKeyList: View {
    let keys: [APIKeyCost]
    private let visible = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel("Keys · this month")
            ForEach(keys.prefix(visible)) { key in
                HStack {
                    Text(key.name).lineLimit(1)
                    Spacer()
                    Text(key.cost ?? "—").monospacedDigit()
                        .foregroundStyle(key.cost == nil ? .secondary : .primary)
                }
                .font(.caption)
            }
            if keys.count > visible {
                Text("+\(keys.count - visible) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "Spending ↗": text first, icon after.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    let reset = Date.now.addingTimeInterval(81_170)
    ClaudeCard(
        claudeAI: SourceState(
            value: ClaudeAIUsage(
                weekly: UsageLimit(key: "weekly_all", title: "This week", percentUsed: 42, resetsAt: reset),
                modelLimits: [UsageLimit(key: "weekly_scoped:fable", title: "Fable", percentUsed: 71, resetsAt: reset,
                                         subtitle: "Up to 50% of your weekly limit")]
            ),
            fetchedAt: .now.addingTimeInterval(-120)
        ),
        platform: SourceState(
            value: PlatformUsage(
                organizationCredits: "$200.69", spendThisMonth: "$2.38", tokenVolume: "160.5K",
                spendLimit: "$60", spendPercent: 3, spendResets: "Dec 1",
                tokenTrend: "Up 136", tokenPeriod: "last 7 days",
                tokenBars: [12.56, 21.61, 30.5, 21.87, 3.73, 8.90, 20.99],
                keys: [
                    APIKeyCost(name: "Koneko", scope: "Miau", cost: "$0.52"),
                    APIKeyCost(name: "miau", scope: "Miau", cost: "$0.32"),
                    APIKeyCost(name: "MacOS OpenCode", scope: "OpenCode", cost: "$0.15"),
                    APIKeyCost(name: "coquelicot-goose", scope: "OpenCode", cost: nil),
                ]
            ),
            fetchedAt: .now
        )
    )
    .padding()
}
