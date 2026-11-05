# AI Usage — iOS Dashboard Spec

Status: Draft v0.1 (2026-11-05)
Owner: Adrian Pata

## 1. Goal

A native iOS app that shows, on one screen, how much of each AI provider's quota and credit you have used and how much you have left:

| Provider | What to show | Where it lives today |
|---|---|---|
| **Claude (subscription)** | Plan usage: current 5‑hour session %, weekly limit %, reset times | claude.ai → Settings → Usage |
| **Claude (API)** | Prepaid credit balance, spend this month, usage by model | platform.claude.com dashboard / billing |
| **Mistral** | Subscription and billing, usage/spend, credits | admin.mistral.ai → Subscription |
| **OpenRouter** | Credit balance, total usage, per-key limits | openrouter.ai → Credits |
| **OpenAI** | Spend this month, usage by model, credit balance; optionally ChatGPT plan limits | platform.openai.com → Usage / Billing |

Non-goals for v1: sending prompts or chatting, team administration, Android, and a web app.

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
| OpenAI spend and usage | `GET /v1/organization/costs`, `GET /v1/organization/usage/completions` (and the other usage endpoints) | A | **Admin** key (`sk-admin-…`), created by an org owner |
| OpenAI prepaid credit balance | No official endpoint known. The dashboard uses internal billing endpoints with a session token | B | Web session |
| ChatGPT Plus/Pro limits | No API | C | n/a |
| Anthropic API spend and usage | Admin API: `/v1/organizations/usage_report/messages`, `/v1/organizations/cost_report` | A | **Admin** key (`sk-ant-admin…`); needs an organization, not an individual account |
| Anthropic prepaid credit balance | No official endpoint known. The platform.claude.com billing page uses internal endpoints | B | Web session |
| Claude.ai plan usage (5h / weekly) | Undocumented `claude.ai/api/organizations/{orgId}/usage` (session cookie), or the OAuth usage endpoint that Claude Code's `/usage` uses | B | `sessionKey` cookie or OAuth token |
| Mistral usage, billing and subscription | No public billing API known. admin.mistral.ai calls internal JSON endpoints behind its web login | B | Web session |

Conclusion: OpenRouter, plus OpenAI and Anthropic *spend*, can be built on official APIs. Claude.ai plan usage, credit *balances* (Anthropic, OpenAI) and everything for Mistral depend on web sessions. The architecture has to support both kinds of source from day one.

## 3. Product requirements

### 3.1 Functional
1. **Dashboard**: one card per configured account. Each card shows a headline metric (for example "$12.40 left" or "Weekly 63%"), a progress ring or bar, secondary metrics, reset or renewal time, and the time of the last refresh.
2. **Detail view** for each provider: a breakdown by model or day where available, and a 30-day spend chart.
3. **Accounts**: add, edit, reorder and delete. Several accounts per provider are allowed (for example personal and work OpenAI orgs).
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
- For Tier B: record the network calls made by claude.ai usage, platform.claude.com billing, admin.mistral.ai subscription and the OpenAI billing page (Safari Web Inspector / HAR). Note the cookie names and whether Cloudflare or bot protection blocks replay from `URLSession`.
- Review each provider's terms on automated access to the dashboard.
- Output: an updated §2.1 table and sample JSON fixtures in `Tests/Fixtures/`.

### Phase 1: Skeleton and Tier A providers (≈1 week)
- Xcode project, `UsageKit` package, models, Keychain wrapper, snapshot store.
- Adapters: **OpenRouter**, **OpenAI (Admin API costs/usage)**, **Anthropic API (Admin cost/usage report)**.
- Add-account flow for API keys, a dashboard with cards, pull-to-refresh.
- Unit tests for the adapters, using fixtures.

### Phase 2: Web-session providers (≈1–1.5 weeks)
- `WebLoginView` and the cookie capture/replay infrastructure.
- Adapters: **Claude.ai plan usage**, **Anthropic credit balance**, **Mistral subscription/usage**, **OpenAI credit balance**.
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
| Admin keys need org-owner rights | Some users can't use Tier A for OpenAI/Anthropic | Explain this in the onboarding. Fall back to Tier B |
| Bot protection (Cloudflare) blocks `URLSession` replay | Tier B fails | Hidden-WebView fetch fallback |
| iOS background refresh is infrequent | Widgets show stale data | Show "updated X min ago", refresh on app foreground |
| Storing powerful admin keys on a phone | Security exposure | Keychain only, optional Face ID, recommend read-only/limited keys where providers support them |

## 7. Open questions

**Scope and product**
1. Is this a **personal-use** app (sideloaded / TestFlight only) or meant for the **App Store**? The answer decides how acceptable Tier B (web-session scraping) is and how much onboarding polish is needed.
2. Exactly which Claude numbers matter? Only the claude.ai plan limits (5‑hour session and weekly %), the API credit balance, monthly API spend, or all of them?
3. For Mistral, what exactly should be shown from the Subscription page: plan name and renewal date, current-month spend, remaining credits, or Le Chat Pro usage? Are you on a Le Chat subscription, API "La Plateforme" pay-as-you-go, or both?
4. For OpenAI: API usage/credits only, or also ChatGPT Plus/Pro limits (which have no API)?
5. Do you need **multiple accounts per provider** (for example personal and company orgs) in v1?
6. Should amounts be shown in the provider's currency (USD, EUR for Mistral), or converted to one currency?
7. Do you want historical charts (needs data retained on device over time), or only current values?
8. Are widgets, notifications/alerts, or an Apple Watch complication required in v1?

**Access and credentials**
9. Are you an **org owner/admin** on OpenAI and Anthropic, able to create Admin API keys? (Without one, spend data has to come from the web session.)
10. Is it acceptable to log in through an in-app web view and store session cookies on the device, given that these sessions expire and may need re-login every few weeks?
11. Would you accept **manual entry** as a fallback for metrics that can't be fetched?
12. Is a small **backend** ever acceptable (for example to poll more often than iOS allows, or to push alerts), or must everything stay on the device?

**Technical**
13. Minimum iOS version: is iOS 17+ OK (needed for SwiftData and interactive widgets)?
14. Desired refresh frequency? Is "every 30–60 min in the background, best effort" enough?
15. Should iCloud sync accounts and settings between devices (iPhone/iPad/Mac Catalyst)? Secrets would need iCloud Keychain.
16. Are there more providers likely soon (Gemini, Groq, DeepSeek, xAI, Perplexity…)? If so, the adapter API should be designed for easy additions, possibly declarative.
17. Does OpenRouter's `/credits` endpoint require a provisioning key now, or does a normal key work? (Verify in Phase 0.)
18. Do official endpoints exist for the Anthropic and OpenAI **prepaid credit balance** that we've missed? (Verify in Phase 0; this would move them from Tier B to Tier A.)
