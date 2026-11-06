import SwiftUI

// Compact building blocks shared by all provider cards.

struct ProviderCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func providerCard() -> some View { modifier(ProviderCardStyle()) }
}

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

/// Bar colour shared by all cards: normal below 70%, orange below 90%, red above.
func usageColor(percent: Double) -> Color {
    switch percent {
    case ..<70: .accentColor
    case ..<90: .orange
    default: .red
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

struct UsageBar: View {
    let percent: Double

    var body: some View {
        ProgressView(value: min(max(percent, 0), 100), total: 100)
            .tint(usageColor(percent: percent))
    }
}

/// Small figure with a label, an optional caption below and an optional trailing view (e.g. a sparkline).
struct StatTile<Trailing: View>: View {
    let label: String
    let value: String?
    var caption: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .center, spacing: 6) {
                Text(value ?? "–")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                trailing()
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension StatTile where Trailing == EmptyView {
    init(label: String, value: String?, caption: String? = nil) {
        self.init(label: label, value: value, caption: caption) { EmptyView() }
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
