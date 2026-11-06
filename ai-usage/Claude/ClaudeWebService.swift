import Foundation
import WebKit

/// Fetches Claude usage through hidden web pages that share the user's web session.
///
/// Neither claude.ai plan usage nor the platform.claude.com figures have an official API, so:
/// - **claude.ai**: the page is pointed at a claude.ai URL and the same JSON endpoint the
///   Usage modal renders from is called with `fetch()` inside it (cookies and Cloudflare
///   behave like a normal visit). If that JSON stops parsing, the Usage modal's DOM is read instead.
/// - **platform.claude.com**: the Console renders server-side and makes no JSON calls for these
///   figures, so scripts read the dashboard cards and the API keys table.
///
/// The pages must stay attached to the view hierarchy (see `HiddenWebPages`) so WebKit
/// doesn't throttle their JavaScript. Helpers live in `WebPageTools`.
final class ClaudeWebService {
    let claudeAIPage = WebDefaults.makePage()
    let platformPage = WebDefaults.makePage()

    /// Raw text from the last fetch of each source, shown in Diagnostics.
    private(set) var lastRaw: [String: String] = [:]

    private static let organizationsURL = URL(string: "https://claude.ai/api/organizations")!
    private static let usageModalURL = URL(string: "https://claude.ai/new#settings/usage")!
    private static let dashboardURL = URL(string: "https://platform.claude.com/dashboard")!
    private static let keysURL = URL(string: "https://platform.claude.com/settings/keys")!

    // MARK: claude.ai

    func fetchClaudeAIUsage() async throws -> ClaudeAIUsage {
        do {
            return try await fetchClaudeAIUsageJSON()
        } catch FetchError.unexpectedResponse(let snippet) {
            // The JSON shape broke: read the Usage modal instead.
            do {
                return try await fetchClaudeAIUsageDOM()
            } catch FetchError.notSignedIn {
                throw FetchError.notSignedIn
            } catch {
                throw FetchError.unexpectedResponse("JSON: \(snippet) · DOM: \(error.localizedDescription)")
            }
        }
    }

    private func fetchClaudeAIUsageJSON() async throws -> ClaudeAIUsage {
        let page = claudeAIPage
        _ = page.load(URLRequest(url: Self.organizationsURL))

        // The document body is the organizations JSON once any Cloudflare check is done.
        let orgsText = try await WebPageTools.poll(timeout: .seconds(25)) { () async throws -> String? in
            guard page.url?.host == "claude.ai", !page.isLoading else { return nil }
            if page.url?.path.contains("login") == true { throw FetchError.notSignedIn }
            let trimmed = await WebPageTools.bodyText(of: page).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("[") || trimmed.hasPrefix("{") ? trimmed : nil
        }
        lastRaw["claude.ai organizations"] = orgsText
        let orgID = try ClaudeUsageParser.organizationID(fromJSON: orgsText)

        let usageText = try await WebPageTools.fetchText(
            "https://claude.ai/api/organizations/\(orgID)/usage",
            in: page
        )
        lastRaw["claude.ai usage"] = usageText
        return try ClaudeUsageParser.usage(fromJSON: usageText)
    }

    private func fetchClaudeAIUsageDOM() async throws -> ClaudeAIUsage {
        let page = claudeAIPage
        _ = page.load(URLRequest(url: Self.usageModalURL))

        let json = try await WebPageTools.poll(timeout: .seconds(25)) { () async throws -> String? in
            if page.url?.path.contains("login") == true { throw FetchError.notSignedIn }
            guard page.url?.host == "claude.ai", !page.isLoading else { return nil }
            let output = await WebPageTools.run(ClaudeScripts.usageDOM, in: page)
            return output.isEmpty ? nil : output
        }
        lastRaw["claude.ai usage DOM"] = json
        return try ClaudeUsageParser.usage(fromDOMJSON: json)
    }

    // MARK: platform.claude.com

    func fetchPlatformUsage() async throws -> PlatformUsage {
        var usage = try await fetchDashboard()

        // A keys failure must not fail the whole source: keep the dashboard figures.
        do {
            usage.keys = try await fetchKeys()
        } catch FetchError.notSignedIn {
            throw FetchError.notSignedIn
        } catch {
            usage.keys = nil
            lastRaw["platform keys"] = (lastRaw["platform keys"] ?? "") + "\nerror: \(error.localizedDescription)"
        }
        return usage
    }

    private func fetchDashboard() async throws -> PlatformUsage {
        let page = platformPage
        _ = page.load(URLRequest(url: Self.dashboardURL))

        var latest: PlatformUsage?
        var latestOutput = ""
        do {
            let output = try await WebPageTools.poll(timeout: .seconds(30)) { () async throws -> String? in
                try Self.checkSignedIn(page)
                guard !page.isLoading, page.url != nil else { return nil }
                let output = await WebPageTools.run(PlatformScripts.dashboard, in: page)
                if output.isEmpty {
                    // Signed-out visitors can get a login form without a "login" URL.
                    if await WebPageTools.hasLoginForm(page) { throw FetchError.notSignedIn }
                    return nil
                }
                latestOutput = output
                let usage = try? ClaudeUsageParser.platformUsage(fromDashboardJSON: output)
                latest = usage
                let complete = usage?.organizationCredits != nil
                    && usage?.spendThisMonth != nil
                    && usage?.tokenVolume != nil
                return complete ? output : nil
            }
            lastRaw["platform dashboard"] = output
            return try ClaudeUsageParser.platformUsage(fromDashboardJSON: output)
        } catch FetchError.timeout {
            lastRaw["platform dashboard"] = latestOutput.isEmpty ? "(script found no cards)" : latestOutput
            // Partial results are better than nothing.
            if let latest, !latest.isEmpty { return latest }
            throw FetchError.unexpectedResponse("Dashboard layout changed")
        }
    }

    private func fetchKeys() async throws -> [APIKeyCost] {
        let page = platformPage
        _ = page.load(URLRequest(url: Self.keysURL))

        let output = try await WebPageTools.poll(timeout: .seconds(20)) { () async throws -> String? in
            try Self.checkSignedIn(page)
            guard !page.isLoading, page.url?.path.hasPrefix("/settings/keys") == true else { return nil }
            let output = await WebPageTools.run(PlatformScripts.keys, in: page)
            if output.isEmpty, await WebPageTools.hasLoginForm(page) { throw FetchError.notSignedIn }
            return output.isEmpty ? nil : output
        }
        lastRaw["platform keys"] = output
        return try ClaudeUsageParser.apiKeys(fromKeysJSON: output)
    }

    /// Login page, or bounced to another host (e.g. claude.com/login) → not signed in.
    private static func checkSignedIn(_ page: WebPage) throws {
        guard let url = page.url, !page.isLoading else { return }
        if url.path.contains("login") || url.path.contains("sign") { throw FetchError.notSignedIn }
        if let host = url.host, host != "platform.claude.com" { throw FetchError.notSignedIn }
    }
}
