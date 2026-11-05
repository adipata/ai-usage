import Foundation

/// One usage bucket from claude.ai (for example "This week" or a model-specific weekly limit).
struct UsageLimit: Codable, Hashable, Identifiable {
    var id: String { key }
    /// Raw key from the claude.ai API, e.g. `seven_day` or `seven_day_fable`.
    let key: String
    let title: String
    /// Percent of the limit used, 0...100.
    let percentUsed: Double
    let resetsAt: Date?
}

/// Plan usage shown on claude.ai → Settings → Usage.
struct ClaudeAIUsage: Codable, Hashable {
    /// "This week" (all models).
    var weekly: UsageLimit?
    /// Model-specific weekly limits (e.g. Fable).
    var modelLimits: [UsageLimit]
    /// Current 5-hour session. Not shown on the card yet, kept for later.
    var session: UsageLimit?
}

/// Figures shown on the platform.claude.com dashboard, kept as display strings
/// exactly as the dashboard renders them (e.g. "$42.10", "1.2M").
struct PlatformUsage: Codable, Hashable {
    var organizationCredits: String?
    var spendThisMonth: String?
    var tokenVolume: String?

    var isEmpty: Bool { organizationCredits == nil && spendThisMonth == nil && tokenVolume == nil }
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
