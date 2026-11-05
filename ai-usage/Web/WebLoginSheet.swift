import SwiftUI
import WebKit

/// Shows the provider's own login page. When the user taps Done, the session
/// cookies are already in the shared website data store.
struct WebLoginSheet: View {
    let site: WebSite
    var onDone: () -> Void = {}

    @State private var page = WebDefaults.makePage()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(page)
                .navigationTitle(site.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reload") { _ = page.load(URLRequest(url: site.loginURL)) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                            onDone()
                        }
                    }
                }
        }
        .onAppear {
            _ = page.load(URLRequest(url: site.loginURL))
        }
    }
}
