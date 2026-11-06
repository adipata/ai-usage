import Foundation

/// Parses the included monthly allowances from admin.mistral.ai → Subscription.
enum MistralUsageParser {
    static let apiLabel = "Included API usage"
    static let vibeCodeLabel = "Included Vibe Code usage"

    /// Mistral doesn't say which time zone the monthly reset uses; Paris is an assumption.
    nonisolated static let resetTimeZone = TimeZone(identifier: "Europe/Paris")!

    // MARK: Script output (primary)

    private struct ScriptOutput: Decodable {
        struct Block: Decodable {
            let used: String?
            let limit: String?
            let reset: String?
            let barPercent: Double?
        }
        let api: Block?
        let vibeCode: Block?
    }

    /// Decodes the output of `MistralScripts.allowances`.
    static func usage(fromJSON text: String, now: Date = .now) throws -> MistralUsage {
        guard let output = try? JSONDecoder().decode(ScriptOutput.self, from: Data(text.utf8)) else {
            throw FetchError.unexpectedResponse(WebPageTools.snippet(text))
        }
        return MistralUsage(
            api: output.api.flatMap { allowance(from: $0, title: "API", now: now) },
            vibeCode: output.vibeCode.flatMap { allowance(from: $0, title: "Vibe Code", now: now) }
        )
    }

    private static func allowance(from block: ScriptOutput.Block, title: String, now: Date) -> Allowance? {
        guard let used = block.used, let limit = block.limit else { return nil }
        // "Resets in 24 days" → "in 24 days"
        let resetText = block.reset.map { text in
            text.lowercased().hasPrefix("resets ") ? String(text.dropFirst("resets ".count)) : text
        }
        return Allowance(
            title: title,
            used: used,
            limit: limit,
            usedValue: number(from: used),
            limitValue: number(from: limit),
            resetText: resetText,
            resetsAt: checkedReset(pageText: resetText, now: now),
            barPercent: block.barPercent
        )
    }

    // MARK: Reset date

    /// 00:00 on the 1st of the month after `date`, in `timeZone`. 31 Dec rolls over to 1 Jan.
    nonisolated static func nextMonthlyReset(after date: Date, timeZone: TimeZone = resetTimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let startOfMonth = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: startOfMonth)
    }

    /// The computed reset, but only if its whole days from `now` match the page's "in N days" (±1).
    /// Otherwise `nil`, so the card shows the page text without a wrong countdown.
    nonisolated static func checkedReset(pageText: String?, now: Date, timeZone: TimeZone = resetTimeZone) -> Date? {
        guard let pageText,
              let reset = nextMonthlyReset(after: now, timeZone: timeZone),
              let pageDays = pageText.split(separator: " ").compactMap({ Int($0) }).first
        else { return nil }
        let computedDays = Int(reset.timeIntervalSince(now) / 86_400)
        return abs(computedDays - pageDays) <= 1 ? reset : nil
    }

    nonisolated static func number(from amount: String) -> Double? {
        UsageFormat.number(from: amount)
    }

    // MARK: Page text (last-resort fallback)

    /// Used only when the script returns nothing. Scans `document.body.innerText`:
    /// the heading, then the next two currency amounts and the "Resets in …" line.
    static func usage(fromPageText text: String, now: Date = .now) -> MistralUsage {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let labels = [apiLabel, vibeCodeLabel]
        return MistralUsage(
            api: allowance(label: apiLabel, title: "API", stopAt: labels, in: lines, now: now),
            vibeCode: allowance(label: vibeCodeLabel, title: "Vibe Code", stopAt: labels, in: lines, now: now)
        )
    }

    static func allowance(label: String, title: String, stopAt labels: [String], in lines: [String], now: Date) -> Allowance? {
        guard let start = lines.firstIndex(where: { $0.lowercased() == label.lowercased() }) else { return nil }

        var amounts: [String] = []
        var reset: String?
        for line in lines[(start + 1)...].prefix(10) {
            let lowered = line.lowercased()
            if labels.contains(where: { $0.lowercased() == lowered }) { break }
            // Only "Resets in …" is the countdown; the description also says "Resets on the first day…".
            if lowered.hasPrefix("resets in ") {
                reset = line
                if amounts.count >= 2 { break }
                continue
            }
            amounts.append(contentsOf: self.amounts(in: line))
        }
        guard amounts.count >= 2 else { return nil }
        return allowance(from: .init(used: amounts[0], limit: amounts[1], reset: reset, barPercent: nil),
                         title: title, now: now)
    }

    /// Currency amounts in a line, e.g. "€0.1", "25,50 €", "$1,234.5".
    static func amounts(in line: String) -> [String] {
        let pattern = #"[€$£]\s?\d[\d.,]*|\d[\d.,]*\s?[€$£]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            Range(match.range, in: line).map { String(line[$0]).trimmingCharacters(in: .whitespaces) }
        }
    }
}
