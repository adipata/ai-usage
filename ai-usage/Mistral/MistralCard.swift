import SwiftUI

/// Compact dashboard card with the included monthly allowances of the Mistral plan.
struct MistralCard: View {
    let state: SourceState<MistralUsage>
    var onSignIn: (WebSite) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Mistral", systemImage: "wind", tint: .orange, updatedAt: state.fetchedAt)

            SectionLabel("Included monthly allowance")
            if let usage = state.value {
                VStack(spacing: 6) {
                    ForEach(usage.allowances) { AllowanceRow(allowance: $0) }
                }
            }
            SourceStatus(state: state, site: .mistral, onSignIn: onSignIn)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// One line: name, bar, "used / limit", reset.
struct AllowanceRow: View {
    let allowance: Allowance

    var body: some View {
        HStack(spacing: 8) {
            Text(allowance.title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            ProgressView(value: min(max(allowance.percentUsed ?? 0, 0), 100), total: 100)
                .tint(usageColor(percent: allowance.percentUsed ?? 0))
            Text("\(allowance.used) / \(allowance.limit)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            Text(allowance.resetText ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MistralCard(state: SourceState(
        value: MistralUsage(
            api: Allowance(title: "API", used: "€0.1", limit: "€25.5", usedValue: 0.1, limitValue: 25.5, resetText: "in 25 days"),
            vibeCode: Allowance(title: "Vibe Code", used: "€1.5", limit: "€255", usedValue: 1.5, limitValue: 255, resetText: "in 25 days")
        ),
        fetchedAt: .now
    ))
    .padding()
}
