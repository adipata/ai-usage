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
        #if os(macOS)
        // macOS sheets size to their content, and a WebView has no intrinsic size.
        .frame(minWidth: 520, idealWidth: 600, minHeight: 680, idealHeight: 760)
        #endif
        .onAppear {
            _ = page.load(URLRequest(url: site.loginURL))
        }
    }
}
