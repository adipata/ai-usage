import Foundation

/// Response shapes observed on 6 Nov 2026 (see "Claude Card — Usage Page Extraction Guide").
enum Fixtures {

    /// claude.ai `/api/organizations/{org}/usage` with the `limits` array.
    static let usageLimits = """
    {
      "five_hour": { "utilization": 12.0, "resets_at": "2026-11-06T22:00:00.123+00:00" },
      "seven_day": { "utilization": 42.0, "resets_at": "2026-11-07T18:00:00.363699+00:00" },
      "seven_day_opus": null,
      "seven_day_sonnet": null,
      "seven_day_oauth_apps": null,
      "tangelo": null,
      "nimbus_quill": null,
      "limits": [
        { "kind": "weekly_all", "group": "weekly", "percent": 42, "severity": "normal",
          "resets_at": "2026-11-07T18:00:00.101717+00:00", "scope": null, "is_active": false },
        { "kind": "weekly_scoped", "group": "weekly", "percent": 71, "severity": "normal",
          "resets_at": "2026-11-07T18:00:00.101854+00:00",
          "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
          "is_active": true }
      ],
      "weekly_scoped_shares": [
        { "limit_index": 1, "used_percent_of_weekly": 36, "allowance_percent_of_weekly": 50 }
      ]
    }
    """

    /// No `limits`; the old `seven_day_<model>` bucket.
    static let usageLegacy = """
    {
      "seven_day": { "utilization": 38.0, "resets_at": "2026-11-07T18:00:00.363699+00:00" },
      "seven_day_fable": { "utilization": 20.0, "resets_at": "2026-11-07T18:00:00+00:00" },
      "seven_day_oauth_apps": { "utilization": 5.0, "resets_at": null }
    }
    """

    /// An unknown kind, a non-weekly group, a missing percent and a scoped entry without a model.
    static let usageOddLimits = """
    {
      "limits": [
        { "kind": "weekly_all", "group": "weekly", "percent": 10, "resets_at": "2026-11-07T18:00:00Z" },
        { "kind": "brand_new_kind", "group": "weekly", "percent": 50 },
        { "kind": "weekly_scoped", "group": "weekly", "percent": null },
        { "kind": "session", "group": "session", "percent": 5 },
        { "kind": "weekly_scoped", "group": "weekly", "percent": 33,
          "scope": { "model": null, "surface": { "display_name": "Claude Code" } } },
        { "kind": "weekly_scoped", "group": "weekly", "percent": 44, "scope": { "model": null, "surface": null } }
      ]
    }
    """

    static let usageDOM = """
    {"weekly":{"name":"This week","percent":42,"reset":"Resets Saturday 7:00 PM"},\
    "scoped":[{"name":"Fable","percent":71,"reset":"Resets Saturday 7:00 PM"}]}
    """

    static let dashboard = """
    {"credits":"$200.69","spend":"$2.38","spendLimit":"$60","spendPercent":3,"spendResets":"Dec 1",\
    "tokens":"160.5K","tokenTrend":"Up 136","tokenPeriod":"last 7 days",\
    "tokenBars":[12.6,21.6,30.5,21.9,3.7,8.9,21.0]}
    """

    static let dashboardPartial = """
    {"credits":"$200.69","spend":"$2.38","spendLimit":"$60","spendPercent":null,"spendResets":"Dec 1",\
    "tokens":"160.5K","tokenTrend":null,"tokenPeriod":"last 7 days"}
    """

    static let keys = """
    {"keys":[{"name":"coquelicot-goose","scope":"OpenCode","cost":null},\
    {"name":"MacOS OpenCode","scope":"OpenCode","cost":"$0.15"},\
    {"name":"Koneko","scope":"Miau","cost":"$0.52"},\
    {"name":"miau","scope":"Miau","cost":"$0.32"}]}
    """

    /// `PlatformUsage` as cached by the first version of the app.
    static let cachedPlatformV1 = """
    {"organizationCredits":"$42.10","spendThisMonth":"$7.84","tokenVolume":"1.2M"}
    """

    static let mistral = """
    {"api":{"used":"€0.1","limit":"€25.5","reset":"Resets in 24 days","barPercent":0.4},\
    "vibeCode":{"used":"€4.02","limit":"€255","reset":"Resets in 24 days","barPercent":1.58}}
    """

    static let mistralNoAPI = """
    {"api":null,"vibeCode":{"used":"€4.02","limit":"€255","reset":"Resets in 24 days","barPercent":1.58}}
    """

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    static let paris = TimeZone(identifier: "Europe/Paris")!

    /// 6 Nov 2026, 19:30 in Paris (18:30 UTC).
    static let now = date("2026-11-06T18:30:00Z")
}
