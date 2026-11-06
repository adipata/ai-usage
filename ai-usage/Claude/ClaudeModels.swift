import Foundation

/// One usage bucket from claude.ai (for example "This week" or a model-specific weekly limit).
struct UsageLimit: Codable, Hashable, Identifiable {
    var id: String { key }
    /// Stable key: `weekly_all`, `weekly_scoped:<title>` (from `limits[]`),
    /// or the legacy bucket name such as `seven_day` / `seven_day_fable`.
    let key: String
    let title: String
    /// Percent of the limit used, 0...100.
    let percentUsed: Double
    let resetsAt: Date?
    /// e.g. "Up to 50% of your weekly limit". Optional so older cached JSON still decodes.
    var subtitle: String? = nil
    /// claude.ai's severity for the limit ("normal", …).
    var severity: String? = nil
    /// True when `resetsAt` was derived from display text ("Resets Saturday 7:00 PM"),
    /// so it is only accurate to about a minute.
    var isApproximateReset: Bool? = nil
}

/// Plan usage shown on claude.ai → Settings → Usage.
struct ClaudeAIUsage: Codable, Hashable {
    /// "This week" (all models).
    var weekly: UsageLimit?
    /// Model-specific weekly limits (e.g. Fable), in the order claude.ai lists them.
    var modelLimits: [UsageLimit]
    /// Current 5-hour session. Not shown on the card yet, kept for later.
    var session: UsageLimit?
}

/// Figures shown on the platform.claude.com dashboard and keys page, kept as display
/// strings exactly as the Console renders them (e.g. "$200.69", "160.5K").
/// Every field added after v1 is optional so older cached JSON still decodes.
struct PlatformUsage: Codable, Hashable {
    var organizationCredits: String?
    var spendThisMonth: String?
    var tokenVolume: String?

    /// "$60" from "of $60 limit".
    var spendLimit: String? = nil
    /// 3 from "3% used".
    var spendPercent: Double? = nil
    /// "Dec 1" from "resets Dec 1".
    var spendResets: String? = nil
    /// "Up 136" / "Down 12".
    var tokenTrend: String? = nil
    /// "last 7 days".
    var tokenPeriod: String? = nil
    /// Relative daily heights of the Token volume sparkline, oldest first. Shape only, not values.
    var tokenBars: [Double]? = nil
    /// API keys with their month-to-date cost, from /settings/keys. `nil` when the keys page failed.
    var keys: [APIKeyCost]? = nil

    var isEmpty: Bool { organizationCredits == nil && spendThisMonth == nil && tokenVolume == nil }
}

/// One row of platform.claude.com → Settings → API keys. The secret is never read.
struct APIKeyCost: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let scope: String?
    /// Month-to-date cost, e.g. "$0.15". `nil` when the page shows "—" (no spend).
    let cost: String?

    var costValue: Double { cost.flatMap(UsageFormat.number(from:)) ?? 0 }
}

/// Last known value of a data source plus the outcome of the most recent fetch.
struct SourceState<Value: Codable & Hashable>: Codable, Hashable {
    var value: Value?
    var fetchedAt: Date?
    var error: String?
    var needsSignIn = false
}

enum FetchError: LocalizedError {
    case notSignedIn
    case timeout
    case unexpectedResponse(String)

    static func isNotSignedIn(_ error: Error) -> Bool {
        if case .notSignedIn? = error as? FetchError { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in"
        case .timeout: "Timed out"
        case .unexpectedResponse(let snippet): "Unexpected response: \(snippet)"
        }
    }
}
