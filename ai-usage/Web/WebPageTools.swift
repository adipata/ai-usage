import Foundation
import WebKit

/// Helpers for reading data out of hidden `WebPage`s that share the user's web session.
enum WebPageTools {

    /// The page's visible text, or "" while it is still navigating.
    static func bodyText(of page: WebPage) async -> String {
        let result = try? await page.callJavaScript("return document.body ? document.body.innerText : ''")
        return result as? String ?? ""
    }

    /// True when the page shows a visible email or password field, i.e. a sign-in form.
    static func hasLoginForm(_ page: WebPage) async -> Bool {
        let script = """
        return [...document.querySelectorAll('input[type=email], input[type=password], input[name=email]')]
            .some(input => input.offsetParent !== null);
        """
        let result = try? await page.callJavaScript(script)
        return result as? Bool ?? false
    }

    /// Runs a script that returns a string (JSON, or '' when the page is not ready).
    /// Returns "" when the script throws or the page is still navigating.
    static func run(_ script: String, in page: WebPage) async -> String {
        let result = try? await page.callJavaScript(script)
        return result as? String ?? ""
    }

    /// The absolute URL of the first element matching a CSS selector that has an href, e.g. `a[href="/subscription"]`.
    static func linkURL(matching selector: String, in page: WebPage) async -> URL? {
        let script = """
        const link = document.querySelector(selector);
        return link && link.href ? link.href : '';
        """
        let result = try? await page.callJavaScript(script, arguments: ["selector": selector])
        guard let href = result as? String, !href.isEmpty else { return nil }
        return URL(string: href)
    }

    /// The absolute URL of the first link whose visible text is `text` (case-insensitive).
    static func linkURL(withText text: String, in page: WebPage) async -> URL? {
        let script = """
        const wanted = text.toLowerCase();
        const link = [...document.querySelectorAll('a[href]')]
            .find(a => a.innerText.trim().toLowerCase() === wanted);
        return link ? link.href : '';
        """
        let result = try? await page.callJavaScript(script, arguments: ["text": text])
        guard let href = result as? String, !href.isEmpty else { return nil }
        return URL(string: href)
    }

    /// Runs `fetch()` inside the page so the request carries the page's cookies.
    static func fetchText(_ url: String, in page: WebPage) async throws -> String {
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
            throw FetchError.unexpectedResponse("HTTP \(status): \(snippet(body))")
        }
        return body
    }

    /// Calls `attempt` every half second until it returns a value or the timeout passes.
    static func poll<T>(timeout: Duration, _ attempt: () async throws -> T?) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            // Sleep first so a navigation that was just started has time to begin.
            try await Task.sleep(for: .milliseconds(500))
            if let value = try await attempt() { return value }
        }
        throw FetchError.timeout
    }

    static func snippet(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }
}
