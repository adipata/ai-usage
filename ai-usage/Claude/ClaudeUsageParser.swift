import Foundation

/// Pure parsing helpers, kept free of WebKit so they can be unit tested.
enum ClaudeUsageParser {

    // MARK: claude.ai

    /// Picks the chat organization from `GET https://claude.ai/api/organizations`.
    static func organizationID(fromJSON text: String) throws -> String {
        let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let orgs = object as? [[String: Any]] else {
            if let dict = object as? [String: Any], dict["error"] != nil || dict["type"] as? String == "error" {
                throw FetchError.notSignedIn
            }
            throw FetchError.unexpectedResponse(snippet(text))
        }
        let chatOrg = orgs.first { org in
            (org["capabilities"] as? [String])?.contains("chat") == true
        }
        guard let uuid = (chatOrg ?? orgs.first)?["uuid"] as? String else {
            throw FetchError.notSignedIn
        }
        return uuid
    }

    /// Parses `GET https://claude.ai/api/organizations/{org}/usage`.
    ///
    /// Expected shape (undocumented, may change):
    /// ```json
    /// { "five_hour":       { "utilization": 12.0, "resets_at": "2026-11-05T15:00:00.123+00:00" },
    ///   "seven_day":       { "utilization": 38.0, "resets_at": "..." },
    ///   "seven_day_fable": { "utilization": 20.0, "resets_at": "..." },
    ///   "seven_day_oauth_apps": null, ... }
    /// ```
    /// Any `seven_day_<name>` bucket is treated as a model-specific weekly limit, so new
    /// models show up without code changes.
    static func usage(fromJSON text: String) throws -> ClaudeAIUsage {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        if object["error"] != nil, object["seven_day"] == nil {
            throw FetchError.notSignedIn
        }

        var limits: [String: UsageLimit] = [:]
        for (key, value) in object {
            guard let bucket = value as? [String: Any],
                  let utilization = (bucket["utilization"] as? NSNumber)?.doubleValue
            else { continue }
            limits[key] = UsageLimit(
                key: key,
                title: title(forKey: key),
                percentUsed: utilization,
                resetsAt: (bucket["resets_at"] as? String).flatMap(parseDate)
            )
        }

        let models = limits.values
            .filter { $0.key.hasPrefix("seven_day_") && !$0.key.contains("oauth") }
            .sorted { $0.title < $1.title }

        guard limits["seven_day"] != nil || !models.isEmpty else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        return ClaudeAIUsage(weekly: limits["seven_day"], modelLimits: models, session: limits["five_hour"])
    }

    static func title(forKey key: String) -> String {
        switch key {
        case "seven_day": return "This week"
        case "five_hour": return "Current session"
        default:
            let name = key.hasPrefix("seven_day_") ? String(key.dropFirst("seven_day_".count)) : key
            return name.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }

    /// ISO 8601 with optional fractional seconds of any length.
    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    // MARK: platform.claude.com

    static let creditsLabel = "Organization credits"
    static let spendLabel = "Spend this month"
    static let tokensLabel = "Token volume"

    /// Extracts the dashboard figures from the rendered page text (`document.body.innerText`).
    static func platformUsage(fromPageText text: String) -> PlatformUsage {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return PlatformUsage(
            organizationCredits: value(after: creditsLabel, in: lines),
            spendThisMonth: value(after: spendLabel, in: lines),
            tokenVolume: value(after: tokensLabel, in: lines)
        )
    }

    /// Finds `label` and returns the first nearby line that contains a digit,
    /// either on the same line ("Spend this month $4.20") or within the next few lines.
    static func value(after label: String, in lines: [String]) -> String? {
        let lowered = label.lowercased()
        guard let index = lines.firstIndex(where: { $0.lowercased().hasPrefix(lowered) }) else { return nil }

        let sameLine = String(lines[index].dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        if containsDigit(sameLine) { return sameLine }

        return lines[(index + 1)...].prefix(4).first(where: containsDigit)
    }

    private static func containsDigit(_ string: String) -> Bool {
        string.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static func snippet(_ text: String) -> String {
        WebPageTools.snippet(text)
    }
}
