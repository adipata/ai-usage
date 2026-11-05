import SwiftUI

/// Compact dashboard card: claude.ai plan limits on top, platform.claude.com figures below.
struct ClaudeCard: View {
    let claudeAI: SourceState<ClaudeAIUsage>
    let platform: SourceState<PlatformUsage>
    var onSignIn: (WebSite) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Claude", systemImage: "sparkle", tint: .orange,
                       updatedAt: [claudeAI.fetchedAt, platform.fetchedAt].compactMap { $0 }.min())

            SectionLabel("claude.ai")
            if let usage = claudeAI.value {
                VStack(spacing: 6) {
                    if let weekly = usage.weekly { LimitRow(limit: weekly) }
                    ForEach(usage.modelLimits) { LimitRow(limit: $0) }
                }
            }
            SourceStatus(state: claudeAI, site: .claudeAI, onSignIn: onSignIn)

            Divider()

            SectionLabel("Platform")
            if let usage = platform.value {
                HStack(alignment: .top, spacing: 8) {
                    StatTile(label: "Credits", value: usage.organizationCredits)
                    StatTile(label: "Spend this month", value: usage.spendThisMonth)
                    StatTile(label: "Tokens", value: usage.tokenVolume)
                }
            }
            SourceStatus(state: platform, site: .claudePlatform, onSignIn: onSignIn)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Reusable compact pieces (shared with future provider cards)

struct CardHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Spacer()
            if let updatedAt {
                Text(updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// One line: name, bar, percent, reset time.
struct LimitRow: View {
    let limit: UsageLimit

    var body: some View {
        HStack(spacing: 8) {
            Text(limit.title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            ProgressView(value: min(max(limit.percentUsed, 0), 100), total: 100)
                .tint(color)
            Text("\(Int(limit.percentUsed.rounded()))%")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 40, alignment: .trailing)
            Text(limit.resetsAt.map(Self.resetText) ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch limit.percentUsed {
        case ..<70: .accentColor
        case ..<90: .orange
        default: .red
        }
    }

    /// "Sat 7:00 PM", matching how claude.ai shows resets.
    static func resetText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

struct StatTile: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value ?? "–")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows an error or sign-in prompt for one source, or nothing when everything is fine.
struct SourceStatus<Value: Codable & Hashable>: View {
    let state: SourceState<Value>
    let site: WebSite
    var onSignIn: (WebSite) -> Void

    var body: some View {
        if state.needsSignIn {
            Button {
                onSignIn(site)
            } label: {
                Label("Sign in to \(site.title)", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        } else if let error = state.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else if state.value == nil {
            Text("Pull to refresh")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ClaudeCard(
        claudeAI: SourceState(
            value: ClaudeAIUsage(
                weekly: UsageLimit(key: "seven_day", title: "This week", percentUsed: 38, resetsAt: .now.addingTimeInterval(200_000)),
                modelLimits: [UsageLimit(key: "seven_day_fable", title: "Fable", percentUsed: 21, resetsAt: .now.addingTimeInterval(200_000))]
            ),
            fetchedAt: .now.addingTimeInterval(-120)
        ),
        platform: SourceState(
            value: PlatformUsage(organizationCredits: "$42.10", spendThisMonth: "$7.84", tokenVolume: "1.2M"),
            fetchedAt: .now
        )
    )
    .padding()
}
