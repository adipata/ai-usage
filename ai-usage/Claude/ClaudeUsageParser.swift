import Foundation

/// Pure parsing helpers, kept free of WebKit so they can be unit tested.
enum ClaudeUsageParser {

    // MARK: - claude.ai organizations

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

    // MARK: - claude.ai usage JSON (primary)

    /// Parses `GET https://claude.ai/api/organizations/{org}/usage` (undocumented).
    ///
    /// Primary source is the `limits` array (observed 6 Nov 2026):
    /// ```json
    /// "limits": [
    ///   { "kind": "weekly_all",    "group": "weekly", "percent": 42, "severity": "normal",
    ///     "resets_at": "2026-11-07T18:00:00.101717+00:00", "scope": null },
    ///   { "kind": "weekly_scoped", "group": "weekly", "percent": 71, "severity": "normal",
    ///     "resets_at": "...", "scope": { "model": { "display_name": "Fable" }, "surface": null } } ],
    /// "weekly_scoped_shares": [ { "limit_index": 1, "allowance_percent_of_weekly": 50 } ]
    /// ```
    /// When `limits` is absent or yields nothing, the legacy `seven_day` / `seven_day_<name>`
    /// buckets are used. When both give a value for the same limit, `limits` wins.
    static func usage(fromJSON text: String) throws -> ClaudeAIUsage {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        if object["error"] != nil, object["seven_day"] == nil, object["limits"] == nil {
            throw FetchError.notSignedIn
        }

        let buckets = legacyBuckets(from: object)
        let fromLimits = limits(from: object)

        let weekly = fromLimits.weekly ?? buckets["seven_day"]
        let modelLimits: [UsageLimit]
        if !fromLimits.scoped.isEmpty {
            modelLimits = fromLimits.scoped   // keep claude.ai's order
        } else {
            modelLimits = buckets.values
                .filter { $0.key.hasPrefix("seven_day_") && !$0.key.contains("oauth") }
                .sorted { $0.title < $1.title }
        }

        guard weekly != nil || !modelLimits.isEmpty else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        return ClaudeAIUsage(weekly: weekly, modelLimits: modelLimits, session: buckets["five_hour"])
    }

    /// Weekly limits from the `limits` array. Unknown kinds and entries without a percent are skipped.
    static func limits(from object: [String: Any]) -> (weekly: UsageLimit?, scoped: [UsageLimit]) {
        guard let entries = object["limits"] as? [[String: Any]] else { return (nil, []) }

        // limit_index → "Up to 50% of your weekly limit"
        var subtitles: [Int: String] = [:]
        for share in object["weekly_scoped_shares"] as? [[String: Any]] ?? [] {
            guard let index = (share["limit_index"] as? NSNumber)?.intValue,
                  let allowance = (share["allowance_percent_of_weekly"] as? NSNumber)?.doubleValue
            else { continue }
            subtitles[index] = "Up to \(Int(allowance.rounded()))% of your weekly limit"
        }

        var weekly: UsageLimit?
        var scoped: [UsageLimit] = []
        for (index, entry) in entries.enumerated() {
            guard entry["group"] as? String == "weekly",
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue
            else { continue }
            let resetsAt = (entry["resets_at"] as? String).flatMap(parseDate)
            let severity = entry["severity"] as? String

            switch entry["kind"] as? String {
            case "weekly_all":
                weekly = UsageLimit(key: "weekly_all", title: "This week", percentUsed: percent,
                                    resetsAt: resetsAt, severity: severity)
            case "weekly_scoped":
                let title = scopeTitle(entry["scope"])
                scoped.append(UsageLimit(key: "weekly_scoped:\(title.lowercased())", title: title,
                                         percentUsed: percent, resetsAt: resetsAt,
                                         subtitle: subtitles[index], severity: severity))
            default:
                continue
            }
        }
        return (weekly, scoped)
    }

    /// `scope.model.display_name`, else the surface's display name, else "Scoped".
    private static func scopeTitle(_ scope: Any?) -> String {
        guard let scope = scope as? [String: Any] else { return "Scoped" }
        if let model = scope["model"] as? [String: Any],
           let name = model["display_name"] as? String, !name.isEmpty {
            return name
        }
        if let surface = scope["surface"] as? [String: Any],
           let name = (surface["display_name"] as? String) ?? (surface["name"] as? String), !name.isEmpty {
            return name
        }
        if let surface = scope["surface"] as? String, !surface.isEmpty {
            return surface.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
        return "Scoped"
    }

    /// Legacy `{ "<bucket>": { "utilization": 42.0, "resets_at": "..." } }` entries, keyed by bucket name.
    private static func legacyBuckets(from object: [String: Any]) -> [String: UsageLimit] {
        var buckets: [String: UsageLimit] = [:]
        for (key, value) in object {
            guard let bucket = value as? [String: Any],
                  let utilization = (bucket["utilization"] as? NSNumber)?.doubleValue
            else { continue }
            buckets[key] = UsageLimit(
                key: key,
                title: title(forKey: key),
                percentUsed: utilization,
                resetsAt: (bucket["resets_at"] as? String).flatMap(parseDate)
            )
        }
        return buckets
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

    /// ISO 8601 with optional fractional seconds of any length (the fraction is dropped).
    nonisolated static func parseDate(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    // MARK: - claude.ai usage DOM (fallback)

    private struct DOMUsage: Decodable {
        struct Row: Decodable {
            let name: String
            let percent: Double?
            let reset: String
        }
        let weekly: Row?
        let scoped: [Row]
    }

    /// Parses the output of `ClaudeScripts.usageDOM` (the Usage modal), used only when the JSON breaks.
    static func usage(fromDOMJSON text: String, now: Date = .now, timeZone: TimeZone = .current) throws -> ClaudeAIUsage {
        guard let dom = try? JSONDecoder().decode(DOMUsage.self, from: Data(text.utf8)) else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        func limit(_ row: DOMUsage.Row, key: String, title: String) -> UsageLimit? {
            guard let percent = row.percent else { return nil }
            let reset = resetDate(fromDisplayText: row.reset, now: now, timeZone: timeZone)
            return UsageLimit(key: key, title: title, percentUsed: percent, resetsAt: reset,
                              isApproximateReset: reset == nil ? nil : true)
        }
        let weekly = dom.weekly.flatMap { limit($0, key: "weekly_all", title: "This week") }
        let scoped = dom.scoped.compactMap { row -> UsageLimit? in
            let title = row.name.isEmpty ? "Scoped" : row.name
            return limit(row, key: "weekly_scoped:\(title.lowercased())", title: title)
        }
        guard weekly != nil || !scoped.isEmpty else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        return ClaudeAIUsage(weekly: weekly, modelLimits: scoped, session: nil)
    }

    /// "Resets Saturday 7:00 PM" → the next Saturday 19:00:00 after `now` in `timeZone`.
    /// Also accepts "today"/"tomorrow" and 24-hour times. Approximate (±1 min): the page shows no seconds.
    /// Anything unparseable → `nil`, so the card shows no countdown rather than a wrong one.
    nonisolated static func resetDate(fromDisplayText text: String, now: Date, timeZone: TimeZone) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = #"^Resets\s+(\w+)\s+(\d{1,2}):(\d{2})\s*([AaPp][Mm])?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        else { return nil }
        func group(_ i: Int) -> String? {
            Range(match.range(at: i), in: trimmed).map { String(trimmed[$0]) }
        }
        guard let dayWord = group(1)?.lowercased(),
              var hour = group(2).flatMap(Int.init),
              let minute = group(3).flatMap(Int.init),
              hour <= 23, minute <= 59
        else { return nil }
        if let meridiem = group(4)?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour != 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        switch dayWord {
        case "today", "tomorrow":
            let base = dayWord == "today" ? now : calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        default:
            var english = Calendar(identifier: .gregorian)
            english.locale = Locale(identifier: "en_US_POSIX")
            let names = english.weekdaySymbols.map { $0.lowercased() }
            let shortNames = english.shortWeekdaySymbols.map { $0.lowercased() }
            guard let index = names.firstIndex(of: dayWord) ?? shortNames.firstIndex(of: dayWord) else { return nil }
            let components = DateComponents(hour: hour, minute: minute, second: 0, weekday: index + 1)
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
        }
    }

    // MARK: - platform.claude.com

    private struct DashboardDTO: Decodable {
        let credits: String?
        let spend: String?
        let spendLimit: String?
        let spendPercent: Double?
        let spendResets: String?
        let tokens: String?
        let tokenTrend: String?
        let tokenPeriod: String?
        let tokenBars: [Double]?
    }

    /// Decodes the output of `PlatformScripts.dashboard`.
    static func platformUsage(fromDashboardJSON text: String) throws -> PlatformUsage {
        guard let dto = try? JSONDecoder().decode(DashboardDTO.self, from: Data(text.utf8)) else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        return PlatformUsage(
            organizationCredits: dto.credits,
            spendThisMonth: dto.spend,
            tokenVolume: dto.tokens,
            spendLimit: dto.spendLimit,
            spendPercent: dto.spendPercent,
            spendResets: dto.spendResets,
            tokenTrend: dto.tokenTrend,
            tokenPeriod: dto.tokenPeriod,
            tokenBars: (dto.tokenBars?.isEmpty ?? true) ? nil : dto.tokenBars
        )
    }

    private struct KeysDTO: Decodable {
        struct Key: Decodable {
            let name: String
            let scope: String?
            let cost: String?
        }
        let keys: [Key]
    }

    /// Decodes the output of `PlatformScripts.keys`, sorted by cost, highest first.
    static func apiKeys(fromKeysJSON text: String) throws -> [APIKeyCost] {
        guard let dto = try? JSONDecoder().decode(KeysDTO.self, from: Data(text.utf8)) else {
            throw FetchError.unexpectedResponse(snippet(text))
        }
        return dto.keys
            .map { APIKeyCost(name: $0.name, scope: $0.scope, cost: $0.cost) }
            .enumerated()
            .sorted { lhs, rhs in
                // Highest cost first; ties keep the page's order.
                lhs.element.costValue != rhs.element.costValue
                    ? lhs.element.costValue > rhs.element.costValue
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func snippet(_ text: String) -> String {
        WebPageTools.snippet(text)
    }
}
