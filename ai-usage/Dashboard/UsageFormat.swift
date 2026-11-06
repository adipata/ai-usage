import Foundation

/// Pure formatting and date helpers shared by all cards. Free of SwiftUI so they can be unit tested.
enum UsageFormat {

    /// Time left until `reset`, rounded down so it never promises more time than there is:
    /// "2d 5h" / "22h 32m" / "14m" / "now". `nil` when there is no reset date.
    ///
    /// Compute it in the view from the current time; never store it (it goes stale between fetches).
    nonisolated static func timeLeft(until reset: Date?, now: Date = .now) -> String? {
        guard let reset else { return nil }
        let seconds = Int(reset.timeIntervalSince(now))
        guard seconds > 60 else { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Absolute reset label, e.g. "Sat 7:00 PM", in the device time zone.
    nonisolated static func resetLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// Parses a display amount for sorting or bars only: "€1,234.5" → 1234.5, "25,5 €" → 25.5, "$0.15" → 0.15.
    nonisolated static func number(from amount: String) -> Double? {
        var digits = amount.filter { $0.isNumber || $0 == "." || $0 == "," }
        if digits.contains(".") && digits.contains(",") {
            // The last separator is the decimal one.
            let decimal: Character = digits.lastIndex(of: ".")! > digits.lastIndex(of: ",")! ? "." : ","
            let thousands: Character = decimal == "." ? "," : "."
            digits.removeAll { $0 == thousands }
            if decimal == "," { digits = digits.replacingOccurrences(of: ",", with: ".") }
        } else if digits.contains(",") {
            // "1,234" and "1,234,567" use commas for thousands; "25,5" uses it as the decimal.
            let parts = digits.split(separator: ",", omittingEmptySubsequences: false)
            let isThousands = parts.count >= 2 && !parts[0].isEmpty && parts[0].count <= 3
                && parts.dropFirst().allSatisfy { $0.count == 3 }
            if isThousands {
                digits.removeAll { $0 == "," }
            } else {
                digits = digits.replacingOccurrences(of: ",", with: ".")
            }
        }
        return Double(digits)
    }
}
