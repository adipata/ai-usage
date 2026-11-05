import Foundation
import WebKit

/// Reads the included monthly allowances from admin.mistral.ai → Subscription.
///
/// There is no public API for this, so the page is rendered in a hidden `WebPage`
/// (sharing the user's web session) and its visible text is parsed.
final class MistralWebService {
    let page = WebDefaults.makePage()

    /// Raw page text from the last fetch, shown in Diagnostics.
    private(set) var lastRaw: String?

    /// Best guess at the Subscription page URL. If the allowances don't appear there,
    /// the service follows the "Subscription" link in the console's navigation instead.
    private static let subscriptionURL = URL(string: "https://admin.mistral.ai/organization/subscription")!

    func fetchUsage() async throws -> MistralUsage {
        _ = page.load(URLRequest(url: Self.subscriptionURL))

        var latest = MistralUsage()
        var latestText = ""
        var attempts = 0
        var followedLink = false
        do {
            _ = try await WebPageTools.poll(timeout: .seconds(30)) { () async throws -> Bool? in
                guard !page.isLoading, let host = page.url?.host else { return nil }
                // Not signed in: the console redirects to its login host (auth.mistral.ai, …).
                guard host == "admin.mistral.ai" else { throw FetchError.notSignedIn }

                let text = await WebPageTools.bodyText(of: page)
                latestText = text
                latest = MistralUsageParser.usage(fromPageText: text)
                if latest.api != nil && latest.vibeCode != nil { return true }

                // After ~3 s without the allowances, try the navigation link once.
                attempts += 1
                if attempts >= 6, !followedLink,
                   let link = await WebPageTools.linkURL(withText: "Subscription", in: page),
                   link != page.url {
                    followedLink = true
                    _ = page.load(URLRequest(url: link))
                }
                return nil
            }
            lastRaw = latestText
            return latest
        } catch FetchError.timeout {
            lastRaw = latestText
            guard latest.isEmpty else { return latest }
            throw FetchError.unexpectedResponse(WebPageTools.snippet(latestText))
        }
    }
}
