import Foundation
import WebKit

/// Websites the app signs in to. Sessions live in the shared, persistent
/// `WKWebsiteDataStore.default()`, so the login sheet and the background
/// fetchers see the same cookies.
enum WebSite: String, CaseIterable, Identifiable {
    case claudeAI
    case claudePlatform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeAI: "claude.ai"
        case .claudePlatform: "platform.claude.com"
        }
    }

    var loginURL: URL {
        switch self {
        case .claudeAI: URL(string: "https://claude.ai/login")!
        case .claudePlatform: URL(string: "https://platform.claude.com/login")!
        }
    }

    /// Matches `WKWebsiteDataRecord.displayName` (the registrable domain).
    var dataRecordDomain: String {
        switch self {
        case .claudeAI: "claude.ai"
        case .claudePlatform: "claude.com"
        }
    }

    /// Removes cookies and storage for this site.
    func signOut() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let matching = records.filter { $0.displayName == dataRecordDomain }
        await store.removeData(ofTypes: types, for: matching)
    }
}

enum WebDefaults {
    /// A Safari user agent. Some sign-in providers (notably Google) refuse to
    /// work inside embedded web views that don't look like Safari.
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func makePage() -> WebPage {
        let page = WebPage()
        page.customUserAgent = userAgent
        return page
    }
}
