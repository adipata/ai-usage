import Foundation

/// One included monthly allowance from admin.mistral.ai → Subscription
/// (e.g. "Included API usage: €0.1 of €25.5, resets in 25 days").
struct Allowance: Codable, Hashable, Identifiable {
    var id: String { title }
    let title: String
    /// Amounts exactly as the page shows them, e.g. "€0.1" and "€25.5".
    let used: String
    let limit: String
    let usedValue: Double?
    let limitValue: Double?
    /// e.g. "in 25 days".
    let resetText: String?
    /// Next reset (00:00 on the 1st of next month, Europe/Paris), only when it agrees with
    /// the page's "in N days". Optional so older cached JSON still decodes.
    var resetsAt: Date? = nil
    /// Percent read from the page's progress bar (cross-check / fallback only).
    var barPercent: Double? = nil

    /// used ÷ limit (0...100), falling back to the page's bar when an amount fails to parse.
    var percentUsed: Double? {
        if let usedValue, let limitValue, limitValue > 0 { return usedValue / limitValue * 100 }
        return barPercent
    }
}

struct MistralUsage: Codable, Hashable {
    var api: Allowance?
    var vibeCode: Allowance?

    var isEmpty: Bool { api == nil && vibeCode == nil }
    var allowances: [Allowance] { [api, vibeCode].compactMap { $0 } }

    /// Note shown on the card when only one allowance was found (e.g. a plan without it).
    var missingNote: String? {
        switch (api, vibeCode) {
        case (nil, .some): "API allowance not found"
        case (.some, nil): "Vibe Code allowance not found"
        default: nil
        }
    }
}
