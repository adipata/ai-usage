import Foundation

/// Reads the included monthly allowances from the rendered Subscription page text.
///
/// The page text looks like this (`document.body.innerText`; headings may be uppercased by CSS):
/// ```
/// Included API usage
/// Included allowance for API/Studio usage. Resets on the first day of each calendar month, ...
/// €0.1
/// €25.5
/// Resets in 25 days
/// Included Vibe Code usage
/// ...
/// ```
enum MistralUsageParser {
    static let apiLabel = "Included API usage"
    static let vibeCodeLabel = "Included Vibe Code usage"

    static func usage(fromPageText text: String) -> MistralUsage {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let labels = [apiLabel, vibeCodeLabel]
        return MistralUsage(
            api: allowance(label: apiLabel, title: "API", stopAt: labels, in: lines),
            vibeCode: allowance(label: vibeCodeLabel, title: "Vibe Code", stopAt: labels, in: lines)
        )
    }

    /// Finds the heading `label`, then collects the first two amounts (used, limit)
    /// and the "Resets …" line that follow it, stopping at the next heading.
    static func allowance(label: String, title: String, stopAt labels: [String], in lines: [String]) -> Allowance? {
        guard let start = lines.firstIndex(where: { $0.lowercased() == label.lowercased() }) else { return nil }

        var amounts: [String] = []
        var resetText: String?
        for line in lines[(start + 1)...].prefix(10) {
            let lowered = line.lowercased()
            if labels.contains(where: { $0.lowercased() == lowered }) { break }
            if lowered.hasPrefix("resets ") {
                resetText = String(line.dropFirst("resets ".count))
                if amounts.count >= 2 { break }
                continue
            }
            amounts.append(contentsOf: self.amounts(in: line))
        }

        guard amounts.count >= 2 else { return nil }
        return Allowance(
            title: title,
            used: amounts[0],
            limit: amounts[1],
            usedValue: number(from: amounts[0]),
            limitValue: number(from: amounts[1]),
            resetText: resetText
        )
    }

    /// Currency amounts in a line, e.g. "€0.1", "25,50 €", "$1,234.5".
    static func amounts(in line: String) -> [String] {
        let pattern = #"[€$£]\s?\d[\d.,\s]*|\d[\d.,]*\s?[€$£]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            Range(match.range, in: line).map { String(line[$0]).trimmingCharacters(in: .whitespaces) }
        }
    }

    /// "€1,234.5" → 1234.5, "25,5 €" → 25.5.
    static func number(from amount: String) -> Double? {
        var digits = amount.filter { $0.isNumber || $0 == "." || $0 == "," }
        if digits.contains(".") && digits.contains(",") {
            // The last separator is the decimal one.
            let decimal: Character = digits.lastIndex(of: ".")! > digits.lastIndex(of: ",")! ? "." : ","
            let thousands: Character = decimal == "." ? "," : "."
            digits.removeAll { $0 == thousands }
            if decimal == "," { digits = digits.replacingOccurrences(of: ",", with: ".") }
        } else if digits.contains(",") {
            digits = digits.replacingOccurrences(of: ",", with: ".")
        }
        return Double(digits)
    }
}
