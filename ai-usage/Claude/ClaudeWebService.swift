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
/// WebKit doesn't throttle their JavaScript.
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
        let orgsText = try await poll(timeout: .seconds(25)) { () async throws -> String? in
            guard page.url?.host == "claude.ai", !page.isLoading else { return nil }
            let text = await self.bodyText(of: page)
            if page.url?.path.contains("login") == true { throw FetchError.notSignedIn }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("[") || trimmed.hasPrefix("{") ? trimmed : nil
        }
        lastRaw["claude.ai organizations"] = orgsText
        let orgID = try ClaudeUsageParser.organizationID(fromJSON: orgsText)

        let usageText = try await fetchText(
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
            let text = try await poll(timeout: .seconds(30)) { () async throws -> String? in
                if let path = page.url?.path, path.contains("login") || path.contains("sign") {
                    throw FetchError.notSignedIn
                }
                guard !page.isLoading, let host = page.url?.host else { return nil }
                // Bounced to a login page on another host (e.g. claude.com/login).
                guard host == "platform.claude.com" else { throw FetchError.notSignedIn }
                let text = await self.bodyText(of: page)
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

    // MARK: Helpers

    /// The page's visible text, or "" while it is still navigating.
    private func bodyText(of page: WebPage) async -> String {
        let result = try? await page.callJavaScript("return document.body ? document.body.innerText : ''")
        return result as? String ?? ""
    }

    /// Runs `fetch()` inside the page so the request carries the page's cookies.
    private func fetchText(_ url: String, in page: WebPage) async throws -> String {
        let script = """
        const response = await fetch(url, { credentials: 'include', headers: { 'Accept': 'application/json' } });
        return JSON.stringify({ status: response.status, body: await response.text() });
        """
        let result = try await page.callJavaScript(script, arguments: ["url": url])
        guard let json = result as? String,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let status = (object["status"] as? NSNumber)?.intValue,
              let body = object["body"] as? String
        else {
            throw FetchError.unexpectedResponse("fetch failed for \(url)")
        }
        if status == 401 || status == 403 { throw FetchError.notSignedIn }
        guard (200..<300).contains(status) else {
            throw FetchError.unexpectedResponse("HTTP \(status): \(ClaudeUsageParser.snippet(body))")
        }
        return body
    }

    /// Calls `attempt` every half second until it returns a value or the timeout passes.
    private func poll<T>(timeout: Duration, _ attempt: () async throws -> T?) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            // Sleep first so a navigation that was just started has time to begin.
            try await Task.sleep(for: .milliseconds(500))
            if let value = try await attempt() { return value }
        }
        throw FetchError.timeout
    }
}
