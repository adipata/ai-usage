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
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 6) {
                        ForEach(usage.allowances) { AllowanceRow(allowance: $0, now: context.date) }
                    }
                }
                if let note = usage.missingNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            SourceStatus(state: state, site: .mistral, onSignIn: onSignIn)
        }
        .providerCard()
    }
}

/// One line: name · bar · "used / limit" · reset ("in 24 days" over the "24d 4h" countdown).
struct AllowanceRow: View {
    let allowance: Allowance
    var now: Date = .now

    var body: some View {
        HStack(spacing: 8) {
            Text(allowance.title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            UsageBar(percent: allowance.percentUsed ?? 0)
            Text("\(allowance.used) / \(allowance.limit)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            // Stacked so the bar keeps its width: page text on top, countdown below.
            VStack(alignment: .trailing, spacing: 0) {
                Text(allowance.resetText ?? "")
                    .foregroundStyle(.secondary)
                if let countdown = UsageFormat.timeLeft(until: allowance.resetsAt, now: now) {
                    Text(countdown)
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let reset = MistralUsageParser.nextMonthlyReset(after: .now)
    MistralCard(state: SourceState(
        value: MistralUsage(
            api: Allowance(title: "API", used: "€0.1", limit: "€25.5", usedValue: 0.1, limitValue: 25.5,
                           resetText: "in 24 days", resetsAt: reset, barPercent: 0.4),
            vibeCode: Allowance(title: "Vibe Code", used: "€4.02", limit: "€255", usedValue: 4.02, limitValue: 255,
                                resetText: "in 24 days", resetsAt: reset, barPercent: 1.58)
        ),
        fetchedAt: .now
    ))
    .padding()
}
