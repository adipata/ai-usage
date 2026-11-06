# AI Usage — iOS Dashboard Spec

Status: Draft v0.4 (2026-11-06): OpenAI dropped. Claude (§8) and Mistral (§9) implemented, revised per the "Claude Card — Usage Page Extraction Guide" doc (§10)
Owner: Adrian Pata

## 1. Goal

A native iOS app that shows, on one screen, how much of each AI provider's quota and credit you have used and how much you have left:

| Provider | What to show | Where it lives today |
|---|---|---|
| **Claude (subscription)** | "This week" % used + reset, model-specific weekly limit (e.g. Fable) % + reset | claude.ai → Settings → Usage |
| **Claude (API)** | Organization credits, Spend this month, Token volume | platform.claude.com → Dashboard |
| **Mistral** | Included monthly allowances: API usage and Vibe Code usage (used / limit in €, reset) | admin.mistral.ai → Subscription |
| **OpenRouter** | Credit balance, total usage, per-key limits | openrouter.ai → Credits |

Non-goals for v1: OpenAI (dropped), sending prompts or chatting, team administration, Android, and a web app.

Layout: one compact card per provider (Claude, Mistral, OpenRouter) so all three fit on roughly one iPhone screen.

## 2. Key constraint: where the data can come from

The providers do not all expose this data through official APIs. Each data point falls into one of three tiers, and the tier decides how robust the integration can be.

- **Tier A, official API with a key.** Stable and documented. Best option.
- **Tier B, undocumented JSON endpoint used by the provider's own web dashboard.** Needs the user's web session (a cookie or OAuth token). Works, but can break without warning and may conflict with the provider's terms.
- **Tier C, nothing machine-readable.** We would have to scrape HTML in a hidden WebView, or ask the user to enter values by hand.

### 2.1 Per-provider data sources (to be verified in Phase 0)

| Provider / metric | Best known source | Tier | Auth |
|---|---|---|---|
| OpenRouter balance and usage | `GET https://openrouter.ai/api/v1/credits` → `total_credits`, `total_usage` | A | API key (may need a provisioning/management key; verify) |
| OpenRouter per-key limit | `GET https://openrouter.ai/api/v1/key` → `usage`, `limit`, `limit_remaining`, daily/weekly/monthly usage | A | API key |
| Anthropic API spend and usage | Admin API: `/v1/organizations/usage_report/messages`, `/v1/organizations/cost_report` | A | **Admin** key (`sk-ant-admin…`); needs an organization, not an individual account |
| Anthropic prepaid credit balance | No official endpoint known. The platform.claude.com billing page uses internal endpoints | B | Web session |
| Claude.ai plan usage (5h / weekly) | Undocumented `claude.ai/api/organizations/{orgId}/usage` (session cookie), or the OAuth usage endpoint that Claude Code's `/usage` uses | B | `sessionKey` cookie or OAuth token |
| Mistral usage, billing and subscription | No public billing API known. admin.mistral.ai calls internal JSON endpoints behind its web login | B | Web session |

Conclusion: OpenRouter and Anthropic *spend* can be built on official APIs. Claude.ai plan usage, the Anthropic credit balance and everything for Mistral depend on web sessions. The architecture has to support both kinds of source from day one.

## 3. Product requirements

### 3.1 Functional
1. **Dashboard**: one card per configured account. Each card shows a headline metric (for example "$12.40 left" or "Weekly 63%"), a progress ring or bar, secondary metrics, reset or renewal time, and the time of the last refresh.
2. **Detail view** for each provider: a breakdown by model or day where available, and a 30-day spend chart.
3. **Accounts**: add, edit, reorder and delete. Several accounts per provider are allowed (for example personal and work Anthropic orgs).
4. **Auth flows**:
   - Paste an API key (Tier A).
   - "Sign in with web" (Tier B): an in-app `WKWebView` opens the provider's login page. After login the app captures the relevant cookies or token and closes the view.
   - Manual entry fallback (Tier C): the user types a value plus a reset date.
5. **Refresh**: pull-to-refresh, refresh on app open, and background refresh (`BGAppRefreshTask`, best effort).
6. **Widgets**: Home Screen and Lock Screen widgets (WidgetKit) with a compact multi-provider view.
7. **Alerts**: local notifications when a threshold is crossed, for example balance below $5 or weekly usage above 80%. Evaluated on refresh.
8. **Stale/error states**: "session expired, sign in again", "rate limited", "endpoint changed".

### 3.2 Non-functional
- **Privacy**: all credentials stay on the device, in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`, so background refresh and widgets can read them). Shared with the widget extension through a Keychain access group. No backend in v1, no analytics on credentials.
- **Optional Face ID** lock for the app.
- **Resilience**: one provider failing never blocks the others. Every adapter has a timeout and returns typed errors.
- **Offline**: show the last known values with a "stale" badge.

## 4. Architecture

- **Platform**: iOS 17+, Swift 6, SwiftUI, Swift Concurrency, SwiftData (or a JSON file) for cached snapshots. No third-party dependencies unless clearly justified. Swift Charts for charts.
- **Targets**: `AIUsage` (app), `AIUsageWidgets` (WidgetKit), `UsageKit` (Swift package with the providers and models, shared by both), plus tests.

### 4.1 Core model
```swift
enum ProviderID: String, Codable { case claudeAI, anthropicAPI, mistral, openRouter, openAI }

struct Account: Identifiable, Codable {
    let id: UUID
    var provider: ProviderID
    var label: String               // "Work", "Personal"
    var authKind: AuthKind          // .apiKey, .adminKey, .webSession, .manual
    // secrets live in Keychain, keyed by account id
}

struct UsageSnapshot: Codable {
    let accountID: UUID
    let fetchedAt: Date
    var metrics: [Metric]
}

struct Metric: Codable, Identifiable {
    let id: String                  // "weekly_limit", "credit_balance", "month_spend"
    var title: String
    var kind: Kind                  // .percentage, .currency(code), .tokens, .count
    var used: Double?
    var limit: Double?
    var remaining: Double?
    var resetsAt: Date?
    var series: [DataPoint]?        // for charts
}
```

### 4.2 Provider adapters
```swift
protocol UsageProvider {
    static var id: ProviderID { get }
    static var supportedAuth: [AuthKind] { get }
    func fetch(account: Account, credentials: Credentials) async throws -> UsageSnapshot
}
```
One adapter per row group in §2.1. Each adapter decodes into private DTOs, then maps them to `Metric`s. The fixtures are recorded JSON responses, so tests run without a network.

### 4.3 Web-session capture (Tier B)
- `WebLoginView` wraps `WKWebView` with a non-persistent `WKWebsiteDataStore` for each account, so accounts stay isolated.
- Each provider declares its login URL, a success predicate (URL pattern or cookie present), and the cookies or headers to keep.
- The captured cookies are stored in the Keychain and replayed with `URLSession`. If replay fails (bot protection, request signing), fall back to running the fetch *inside* a hidden `WKWebView` (`callAsyncJavaScript` + `fetch()`), which reuses the real browser context.
- Detect expiry from 401/403 responses or a login redirect, then mark the account "needs sign-in" and notify the user.

### 4.4 Refresh pipeline
`RefreshCoordinator` (actor) → fetches all accounts concurrently with a `TaskGroup` → persists snapshots → reloads widget timelines (`WidgetCenter.shared.reloadAllTimelines()`) → evaluates alert rules. Background task scheduled about every 30 min (iOS decides the actual timing). Widgets read the cached snapshots from the App Group container and never hit the network themselves in v1.

## 5. Implementation plan

### Phase 0: Discovery spike (1–2 days)
- Confirm every endpoint in §2.1: request shape, response, auth, rate limits.
- For Tier B: record the network calls made by claude.ai usage, platform.claude.com billing, and admin.mistral.ai subscription (Safari Web Inspector / HAR). Note the cookie names and whether Cloudflare or bot protection blocks replay from `URLSession`.
- Review each provider's terms on automated access to the dashboard.
- Output: an updated §2.1 table and sample JSON fixtures in `Tests/Fixtures/`.

### Phase 1: Skeleton and Tier A providers (≈1 week)
- Xcode project, `UsageKit` package, models, Keychain wrapper, snapshot store.
- Adapters: **OpenRouter**, **Anthropic API (Admin cost/usage report)** (optional, see §8).
- Add-account flow for API keys, a dashboard with cards, pull-to-refresh.
- Unit tests for the adapters, using fixtures.

### Phase 2: Web-session providers (≈1–1.5 weeks)
- `WebLoginView` and the cookie capture/replay infrastructure.
- Adapters: **Claude.ai plan usage**, **Anthropic credit balance**, **Mistral subscription/usage**.
- Session-expiry handling and a re-login prompt.

### Phase 3: Widgets, background refresh, alerts (≈1 week)
- App Group, shared Keychain access group, WidgetKit (small/medium plus Lock Screen accessory).
- `BGAppRefreshTask`, threshold rules UI, local notifications.

### Phase 4: Polish and release (≈1 week)
- Detail views with Swift Charts, empty/error states, Face ID lock, accessibility, dark mode, app icon.
- TestFlight. Decide whether to distribute through the App Store or keep it personal (see open questions).

### Testing
- Unit: DTO decoding against fixtures, metric mapping, refresh coordinator with mocked providers.
- Integration (manual or opt-in): live calls with real keys from a local, git-ignored `.xcconfig`.
- UI: snapshot tests of the dashboard cards in their states (ok, warning, stale, error).

## 6. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Undocumented endpoints change | Tier B cards break | Isolate per adapter, clear "endpoint changed" error, fast patch releases, manual fallback |
| Terms-of-service restrictions on automated dashboard access | App Store rejection or account risk | Review the terms in Phase 0. Prefer official APIs. Keep Tier B optional and clearly labelled |
| Admin keys need org-owner rights | Some users can't use Tier A for Anthropic | Explain this in the onboarding. Fall back to Tier B |
| Bot protection (Cloudflare) blocks `URLSession` replay | Tier B fails | Hidden-WebView fetch fallback |
| iOS background refresh is infrequent | Widgets show stale data | Show "updated X min ago", refresh on app foreground |
| Storing powerful admin keys on a phone | Security exposure | Keychain only, optional Face ID, recommend read-only/limited keys where providers support them |

## 7. Open questions

**Scope and product**
1. Is this a **personal-use** app (sideloaded / TestFlight only) or meant for the **App Store**? The answer decides how acceptable Tier B (web-session scraping) is and how much onboarding polish is needed.
2. Exactly which Claude numbers matter? Only the claude.ai plan limits (5‑hour session and weekly %), the API credit balance, monthly API spend, or all of them?
3. ~~Mistral scope~~ Resolved: the two included monthly allowances (API and Vibe Code) from the Subscription page.
4. ~~OpenAI scope~~ Resolved: OpenAI is dropped.
5. Do you need **multiple accounts per provider** (for example personal and company orgs) in v1?
6. Should amounts be shown in the provider's currency (USD, EUR for Mistral), or converted to one currency?
7. Do you want historical charts (needs data retained on device over time), or only current values?
8. Are widgets, notifications/alerts, or an Apple Watch complication required in v1?

**Access and credentials**
9. Are you an **org owner/admin** on Anthropic, able to create Admin API keys? (Without one, spend data has to come from the web session.)
10. Is it acceptable to log in through an in-app web view and store session cookies on the device, given that these sessions expire and may need re-login every few weeks?
11. Would you accept **manual entry** as a fallback for metrics that can't be fetched?
12. Is a small **backend** ever acceptable (for example to poll more often than iOS allows, or to push alerts), or must everything stay on the device?

**Technical**
13. Minimum iOS version: is iOS 17+ OK (needed for SwiftData and interactive widgets)?
14. Desired refresh frequency? Is "every 30–60 min in the background, best effort" enough?
15. Should iCloud sync accounts and settings between devices (iPhone/iPad/Mac Catalyst)? Secrets would need iCloud Keychain.
16. Are there more providers likely soon (Gemini, Groq, DeepSeek, xAI, Perplexity…)? If so, the adapter API should be designed for easy additions, possibly declarative.
17. Does OpenRouter's `/credits` endpoint require a provisioning key now, or does a normal key work? (Verify in Phase 0.)
18. Do official endpoints exist for the Anthropic **prepaid credit balance** that we've missed? (Verify in Phase 0; this would move them from Tier B to Tier A.)

## 8. Claude implementation (v1, done)

**Data sources:** both are web-session based, using the SwiftUI WebKit API (`WebPage`/`WebView`, iOS 26+):

| Metric | How it is read |
|---|---|
| This week (% used, reset) | `GET claude.ai/api/organizations` → pick the org with the `chat` capability → `GET claude.ai/api/organizations/{uuid}/usage` → `seven_day.utilization` / `seven_day.resets_at` |
| Fable (% used, reset) | Same response, `seven_day_<model>` buckets. Every such bucket is shown, so new models appear automatically. `seven_day_oauth_apps` is ignored |
| Organization credits / Spend this month / Token volume | `platform.claude.com/dashboard` is rendered in a hidden page. Its `document.body.innerText` is scanned for each label, and the first nearby line with a digit is taken as the value, kept as the display string |

- The claude.ai calls are made with `fetch()` *inside* a hidden page on the claude.ai origin, so they carry the browser's cookies and pass Cloudflare like a normal visit.
- Sign-in uses the provider's own login page in a sheet, with a Safari user agent so Google sign-in is not blocked. All cookies live in `WKWebsiteDataStore.default()`. Sign-out removes that domain's website data.
- The hidden pages stay attached to the view hierarchy (invisible, 390×844) so WebKit does not throttle them.
- The last results are cached in `UserDefaults` and shown on launch. A sign-in prompt appears on a source when its session is missing or expired.
- Accounts → Diagnostics shows the raw responses from the last fetch, to fix parsing when the pages or endpoints change.

**Files** (`ai-usage/`):
- `Claude/ClaudeModels.swift`: data models
- `Claude/ClaudeUsageParser.swift`: pure parsing, unit-testable
- `Claude/ClaudeWebService.swift`: fetching
- `Claude/ClaudeCard.swift`: the card, plus compact components to reuse for other providers
- `Web/`: sign-in sheet and site definitions
- `Dashboard/UsageStore.swift`: state and cache
- `Settings/AccountsView.swift`: accounts and diagnostics

**Open questions for Claude:**
19. ~~Resolved~~: it comes from `weekly_scoped_shares[].allowance_percent_of_weekly` and is stored as the limit's `subtitle`. The claude.ai Usage page shows "Up to 50% of your weekly limit" under Fable. Is that a fixed cap description (static text), or a figure that changes? The usage JSON may not contain it. If it matters, scrape it from `claude.ai/settings/usage`.
20. ~~Resolved~~: no. Fable is a `weekly_scoped` entry in `limits[]`. Is the Fable bucket key really `seven_day_<model>`? Check the raw response in Diagnostics on first run. The parser picks up any `seven_day_*` key.
21. Is scraping the platform dashboard text acceptable, or should spend and tokens come from the official Admin API (cost report / usage report) using an Admin key? That would be more robust, but the credit balance would still need the dashboard.
22. If you belong to several platform organizations, which one should be shown? Currently it is whichever the dashboard opens by default.
23. Should the current 5‑hour session also be shown? It is already parsed.

## 9. Mistral implementation (v1, done)

| Metric | How it is read |
|---|---|
| Included API usage (used, limit, reset) | admin.mistral.ai Subscription page, rendered in a hidden page. In `document.body.innerText`, find the "Included API usage" heading, then take the next two currency amounts (used, limit) and the "Resets …" line, stopping at the next heading |
| Included Vibe Code usage | Same, under the "Included Vibe Code usage" heading |

- The page URL is a guess (`/organization/subscription`). If the allowances don't show up there within about 3 seconds, the app follows the console's "Subscription" navigation link once.
- If the page redirects to another host (Mistral's login), the card shows "Sign in to admin.mistral.ai".
- Amounts are kept as displayed (e.g. "€0.1 / €25.5"), and parsed into numbers only to draw the bar. Both "1,234.5" and "25,5" formats are handled.
- Files: `ai-usage/Mistral/` (models, parser, service, card). Shared web helpers are in `ai-usage/Web/WebPageTools.swift`.

**Open questions for Mistral:**
24. ~~Resolved~~: `https://admin.mistral.ai/subscription`. What is the real URL of the Subscription page? Replace the guess once it's known.
25. Can sign-in finish inside the app's web view? (For example, if it uses Google or a passkey, or a magic link that opens in Safari.)
26. Is "Resets in 25 days" enough, or should the card show a date ("1 Dec")? It's always the 1st of next month, so it could be computed.

## 10. Revision per the extraction guide (2026-11-06)

This section supersedes the data-source details in §8 and §9.

**claude.ai**
- Primary source: `limits[]` in `/api/organizations/{org}/usage`. `weekly_all` gives "This week"; each `weekly_scoped` gives a model row (title from `scope.model.display_name`), kept in claude.ai's order. `weekly_scoped_shares` supplies the subtitle ("Up to 50% of your weekly limit").
- Falls back to the legacy `seven_day*` buckets when `limits` is missing. When the JSON breaks entirely, it falls back to the Usage modal's DOM (`claude.ai/new#settings/usage`, `[data-testid="pace-week"]` meters). In that case the reset comes from "Resets Saturday 7:00 PM" and is approximate (±1 min).
- Every row shows the absolute reset ("Sat 7:00 PM") next to a countdown ("22h 32m", rounded down). The countdown is computed in the view, refreshed every minute by a `TimelineView`, and never stored.

**platform.claude.com**
- Dashboard: one script reads each `[data-cds="Card"]`, found by its title link's href (`/settings/billing`, `/cost…`, an exact `/usage`). Output: credits, spend plus limit, % and reset, tokens plus trend and period, and the 7 sparkline bar heights.
- Keys: a script reads `/settings/keys`, finding columns by header text. The key name comes from the row button's aria-label, and the masked secret is never read. Each key shows its month-to-date cost, sorted by cost, top 5 plus "+N more". If the keys page fails, the dashboard figures are still shown.
- The section header has a "Spending ↗" link to `platform.claude.com/spending`, which opens in Safari.

**Mistral**
- Loads `https://admin.mistral.ai/subscription` directly. If needed, follows the `a[href="/subscription"]` nav link as a fallback.
- A block-scoped script finds each allowance by its heading text, climbs to the block, and reads the two amounts, the "Resets in N days" line and the progress-bar percent.
- Countdown to 00:00 on the 1st of next month, Europe/Paris (an assumption). It is shown only when its whole days match the page's "in N days" (±1).

**Other**
- The app refetches when it comes to the foreground and the data is older than 15 minutes or a reset time has passed.
- All scripts live in `Claude/ClaudeScripts.swift` and `Mistral/MistralScripts.swift`. Shared UI pieces are in `Dashboard/CardComponents.swift`, and formatting in `Dashboard/UsageFormat.swift`.
- Unit tests live in `ai-usageTests/` (Swift Testing; fixtures from the guide). To run them, add a Unit Testing Bundle target named `ai-usageTests` in Xcode, with that folder as its source, hosted by the `ai-usage` app.

