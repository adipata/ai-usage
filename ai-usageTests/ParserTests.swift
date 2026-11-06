import Foundation
import Testing
@testable import ai_usage

@MainActor
struct ClaudeAIUsageTests {

    @Test func limitsArrayIsPrimary() throws {
        let usage = try ClaudeUsageParser.usage(fromJSON: Fixtures.usageLimits)
        let reset = Fixtures.date("2026-11-07T18:00:00Z")

        #expect(usage.weekly?.percentUsed == 42)
        #expect(usage.weekly?.title == "This week")
        #expect(usage.weekly?.resetsAt == reset)

        #expect(usage.modelLimits.count == 1)
        let fable = try #require(usage.modelLimits.first)
        #expect(fable.title == "Fable")
        #expect(fable.key == "weekly_scoped:fable")
        #expect(fable.percentUsed == 71)
        #expect(fable.resetsAt == reset)
        #expect(fable.subtitle == "Up to 50% of your weekly limit")
    }

    @Test func legacyBucketsStillWork() throws {
        let usage = try ClaudeUsageParser.usage(fromJSON: Fixtures.usageLegacy)
        #expect(usage.weekly?.percentUsed == 38)
        #expect(usage.modelLimits.map(\.title) == ["Fable"])
    }

    @Test func oddLimitsDoNotCrash() throws {
        let usage = try ClaudeUsageParser.usage(fromJSON: Fixtures.usageOddLimits)
        #expect(usage.weekly?.percentUsed == 10)
        #expect(usage.modelLimits.map(\.title) == ["Claude Code", "Scoped"])
        #expect(usage.modelLimits.map(\.percentUsed) == [33, 44])
    }

    @Test func domFallback() throws {
        let usage = try ClaudeUsageParser.usage(fromDOMJSON: Fixtures.usageDOM, now: Fixtures.now, timeZone: Fixtures.paris)
        // Saturday 7 Nov 2026, 19:00 in Paris = 18:00 UTC.
        let expected = Fixtures.date("2026-11-07T18:00:00Z")
        #expect(usage.weekly?.percentUsed == 42)
        #expect(usage.weekly?.resetsAt == expected)
        #expect(usage.modelLimits.first?.title == "Fable")
        #expect(usage.modelLimits.first?.percentUsed == 71)
        #expect(usage.modelLimits.first?.resetsAt == expected)
        #expect(usage.modelLimits.first?.isApproximateReset == true)
    }

    @Test func unparseableResetTextGivesNil() {
        #expect(ClaudeUsageParser.resetDate(fromDisplayText: "Resets soon", now: Fixtures.now, timeZone: Fixtures.paris) == nil)
        #expect(ClaudeUsageParser.resetDate(fromDisplayText: "", now: Fixtures.now, timeZone: Fixtures.paris) == nil)
    }
}

@MainActor
struct TimeLeftTests {
    let now = Fixtures.now

    @Test func formats() {
        func left(_ seconds: Int) -> String? {
            UsageFormat.timeLeft(until: now.addingTimeInterval(TimeInterval(seconds)), now: now)
        }
        #expect(left(2 * 86_400 + 5 * 3_600 + 59 * 60) == "2d 5h")
        #expect(left(22 * 3_600 + 32 * 60 + 50) == "22h 32m")
        #expect(left(14 * 60) == "14m")
        #expect(left(30) == "now")
        #expect(left(-300) == "now")
        #expect(UsageFormat.timeLeft(until: nil, now: now) == nil)
    }

    @Test func guideExample() {
        // 6 Nov 2026 19:28 UTC → 7 Nov 18:00 UTC = 22h 32m.
        let now = Fixtures.date("2026-11-06T19:28:00Z")
        #expect(UsageFormat.timeLeft(until: Fixtures.date("2026-11-07T18:00:00Z"), now: now) == "22h 32m")
    }

    @Test func numbers() {
        #expect(UsageFormat.number(from: "€0.1") == 0.1)
        #expect(UsageFormat.number(from: "25,5 €") == 25.5)
        #expect(UsageFormat.number(from: "€1,234.50") == 1234.5)
        #expect(UsageFormat.number(from: "$1,234") == 1234)
        #expect(UsageFormat.number(from: "$0.15") == 0.15)
    }
}

@MainActor
struct PlatformTests {

    @Test func dashboardDecodes() throws {
        let usage = try ClaudeUsageParser.platformUsage(fromDashboardJSON: Fixtures.dashboard)
        #expect(usage.organizationCredits == "$200.69")
        #expect(usage.spendThisMonth == "$2.38")
        #expect(usage.spendLimit == "$60")
        #expect(usage.spendPercent == 3)
        #expect(usage.spendResets == "Dec 1")
        #expect(usage.tokenVolume == "160.5K")
        #expect(usage.tokenTrend == "Up 136")
        #expect(usage.tokenPeriod == "last 7 days")
        #expect(usage.tokenBars?.count == 7)
    }

    @Test func partialDashboardDecodes() throws {
        let usage = try ClaudeUsageParser.platformUsage(fromDashboardJSON: Fixtures.dashboardPartial)
        #expect(usage.spendPercent == nil)
        #expect(usage.tokenBars == nil)   // graph hidden
        #expect(usage.tokenTrend == nil)
    }

    @Test func keysSortedByCost() throws {
        let keys = try ClaudeUsageParser.apiKeys(fromKeysJSON: Fixtures.keys)
        #expect(keys.map(\.name) == ["Koneko", "miau", "MacOS OpenCode", "coquelicot-goose"])
        #expect(keys.last?.cost == nil)
    }

    @Test func oldCacheStillDecodes() throws {
        let usage = try JSONDecoder().decode(PlatformUsage.self, from: Data(Fixtures.cachedPlatformV1.utf8))
        #expect(usage.organizationCredits == "$42.10")
        #expect(usage.keys == nil)
    }
}

@MainActor
struct MistralTests {

    @Test func scriptOutputDecodes() throws {
        let usage = try MistralUsageParser.usage(fromJSON: Fixtures.mistral, now: Fixtures.now)
        let api = try #require(usage.api)
        let vibe = try #require(usage.vibeCode)

        #expect(api.used == "€0.1")
        #expect(api.limit == "€25.5")
        #expect(abs((api.percentUsed ?? 0) - 0.39) < 0.01)
        #expect(api.resetText == "in 24 days")

        #expect(vibe.used == "€4.02")
        #expect(vibe.limit == "€255")
        #expect(abs((vibe.percentUsed ?? 0) - 1.58) < 0.01)

        // 1 Dec 2026 00:00 in Paris = 30 Nov 23:00 UTC.
        #expect(api.resetsAt == Fixtures.date("2026-11-30T23:00:00Z"))
        #expect(usage.missingNote == nil)
    }

    @Test func missingAPIAllowance() throws {
        let usage = try MistralUsageParser.usage(fromJSON: Fixtures.mistralNoAPI, now: Fixtures.now)
        #expect(usage.api == nil)
        #expect(usage.vibeCode != nil)
        #expect(usage.missingNote == "API allowance not found")
    }

    @Test func nextMonthlyReset() {
        let reset = MistralUsageParser.nextMonthlyReset(after: Fixtures.now, timeZone: Fixtures.paris)
        #expect(reset == Fixtures.date("2026-11-30T23:00:00Z"))

        // 31 Dec rolls over to 1 Jan of the next year.
        let newYearsEve = Fixtures.date("2026-12-31T12:00:00Z")
        #expect(MistralUsageParser.nextMonthlyReset(after: newYearsEve, timeZone: Fixtures.paris)
                == Fixtures.date("2026-12-31T23:00:00Z"))
    }

    @Test func crossCheck() {
        #expect(MistralUsageParser.checkedReset(pageText: "in 24 days", now: Fixtures.now, timeZone: Fixtures.paris) != nil)
        #expect(MistralUsageParser.checkedReset(pageText: "in 3 days", now: Fixtures.now, timeZone: Fixtures.paris) == nil)
        #expect(MistralUsageParser.checkedReset(pageText: nil, now: Fixtures.now, timeZone: Fixtures.paris) == nil)
    }
}
