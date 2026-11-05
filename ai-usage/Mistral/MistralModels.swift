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

    /// 0...100 when both amounts could be parsed.
    var percentUsed: Double? {
        guard let usedValue, let limitValue, limitValue > 0 else { return nil }
        return usedValue / limitValue * 100
    }
}

struct MistralUsage: Codable, Hashable {
    var api: Allowance?
    var vibeCode: Allowance?

    var isEmpty: Bool { api == nil && vibeCode == nil }
    var allowances: [Allowance] { [api, vibeCode].compactMap { $0 } }
}
