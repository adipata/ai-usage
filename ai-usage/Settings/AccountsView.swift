import SwiftUI

/// Sign in / out of each web account, plus raw responses for debugging.
struct AccountsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var loginSite: WebSite?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WebSite.allCases) { site in
                        HStack {
                            Text(site.title)
                            Spacer()
                            Button("Sign in") { loginSite = site }
                                .buttonStyle(.borderless)
                            Button("Sign out", role: .destructive) {
                                Task { await store.signOut(site) }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Web accounts")
                } footer: {
                    Text("You sign in on the provider's own page. The session stays on this device and is used to read your usage.")
                }

                Section("Diagnostics") {
                    NavigationLink("Last raw responses") {
                        RawResponsesView(responses: store.rawResponses)
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $loginSite) { site in
                WebLoginSheet(site: site) {
                    Task { await store.refresh() }
                }
            }
        }
    }
}

private struct RawResponsesView: View {
    let responses: [String: String]

    var body: some View {
        List {
            if responses.isEmpty {
                Text("Nothing fetched yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(responses.keys.sorted(), id: \.self) { key in
                Section(key) {
                    Text(responses[key] ?? "")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Raw responses")
    }
}
