import Foundation
import WebKit

/// Reads the included monthly allowances from admin.mistral.ai → Subscription.
///
/// admin.mistral.ai renders the allowances server-side and makes no JSON call that carries
/// them, so the page is rendered in a hidden `WebPage` (sharing the user's web session) and a
/// block-scoped script reads them.
final class MistralWebService {
    let page = WebDefaults.makePage()

    /// Script output (or page text) from the last fetch, shown in Diagnostics.
    private(set) var lastRaw: String?

    private static let subscriptionURL = URL(string: "https://admin.mistral.ai/subscription")!

    func fetchUsage() async throws -> MistralUsage {
        _ = page.load(URLRequest(url: Self.subscriptionURL))

        var latest = MistralUsage()
        var latestOutput = ""
        var attempts = 0
        var followedLink = false
        do {
            _ = try await WebPageTools.poll(timeout: .seconds(30)) { () async throws -> Bool? in
                guard !page.isLoading, let host = page.url?.host else { return nil }
                // Not signed in: the console redirects to its login host (auth.mistral.ai, …).
                guard host == "admin.mistral.ai" else { throw FetchError.notSignedIn }

                let output = await WebPageTools.run(MistralScripts.allowances, in: page)
                if !output.isEmpty, let usage = try? MistralUsageParser.usage(fromJSON: output) {
                    latestOutput = output
                    latest = usage
                    if usage.api != nil && usage.vibeCode != nil { return true }
                }

                // After ~5 s without both allowances, follow the console's nav link once
                // (in case the page moved), then keep waiting.
                attempts += 1
                if attempts >= 10, !followedLink,
                   let link = await WebPageTools.linkURL(matching: #"a[href="/subscription"]"#, in: page),
                   link != page.url {
                    followedLink = true
                    _ = page.load(URLRequest(url: link))
                }
                return nil
            }
            lastRaw = latestOutput
            return latest
        } catch FetchError.timeout {
            if !latest.isEmpty {
                // A plan without one of the allowances (e.g. Free) shows only the other.
                lastRaw = latestOutput
                return latest
            }
            // Last resort: the old page-text parser.
            let text = await WebPageTools.bodyText(of: page)
            lastRaw = "script: \(latestOutput.isEmpty ? "(nothing)" : latestOutput)\n\npage text:\n\(text)"
            let fallback = MistralUsageParser.usage(fromPageText: text)
            guard fallback.isEmpty else { return fallback }
            throw FetchError.unexpectedResponse("Allowances not found: \(WebPageTools.snippet(text))")
        }
    }
}
