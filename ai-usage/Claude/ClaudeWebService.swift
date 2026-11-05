import Foundation
import WebKit

/// Fetches Claude usage through hidden web pages that share the user's web session.
///
/// Neither claude.ai plan usage nor the platform.claude.com dashboard figures have
/// an official API, so:
/// - **claude.ai**: the page is pointed at a claude.ai URL and the same JSON
///   endpoints the Usage settings page uses are called with `fetch()` from inside
///   it, which reuses the browser's cookies and passes Cloudflare like a normal visit.
/// - **platform.claude.com**: the dashboard is rendered and its visible text is
///   read, then the three figures are picked out next to their labels.
///
/// The pages must stay attached to the view hierarchy (see `HiddenWebPages`) so
/// WebKit doesn't throttle their JavaScript. Helpers live in `WebPageTools`.
final class ClaudeWebService {
    let claudeAIPage = WebDefaults.makePage()
    let platformPage = WebDefaults.makePage()

    /// Raw text from the last fetch of each source, shown in Diagnostics.
    private(set) var lastRaw: [String: String] = [:]

    private static let organizationsURL = URL(string: "https://claude.ai/api/organizations")!
    private static let dashboardURL = URL(string: "https://platform.claude.com/dashboard")!

    // MARK: claude.ai

    func fetchClaudeAIUsage() async throws -> ClaudeAIUsage {
        let page = claudeAIPage
        _ = page.load(URLRequest(url: Self.organizationsURL))

        // The document body is the organizations JSON once any Cloudflare check is done.
        let orgsText = try await WebPageTools.poll(timeout: .seconds(25)) { () async throws -> String? in
            guard page.url?.host == "claude.ai", !page.isLoading else { return nil }
            let text = await WebPageTools.bodyText(of: page)
            if page.url?.path.contains("login") == true { throw FetchError.notSignedIn }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: platform.claude.com

    func fetchPlatformUsage() async throws -> PlatformUsage {
        let page = platformPage
        _ = page.load(URLRequest(url: Self.dashboardURL))

        var latest = PlatformUsage()
        var latestText = ""
        do {
            // The dashboard is a single-page app; wait until all three figures have rendered.
            let text = try await WebPageTools.poll(timeout: .seconds(30)) { () async throws -> String? in
                if let path = page.url?.path, path.contains("login") || path.contains("sign") {
                    throw FetchError.notSignedIn
                }
                guard !page.isLoading, let host = page.url?.host else { return nil }
                // Bounced to a login page on another host (e.g. claude.com/login).
                guard host == "platform.claude.com" else { throw FetchError.notSignedIn }
                let text = await WebPageTools.bodyText(of: page)
                latestText = text
                latest = ClaudeUsageParser.platformUsage(fromPageText: text)
                let complete = latest.organizationCredits != nil
                    && latest.spendThisMonth != nil
                    && latest.tokenVolume != nil
                return complete ? text : nil
            }
            lastRaw["platform dashboard"] = text
            return latest
        } catch FetchError.timeout {
            lastRaw["platform dashboard"] = latestText
            // Partial results are better than nothing.
            guard latest.isEmpty else { return latest }
            throw FetchError.unexpectedResponse(ClaudeUsageParser.snippet(latestText))
        }
    }
}
