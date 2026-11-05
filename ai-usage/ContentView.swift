import SwiftUI
import WebKit

struct ContentView: View {
    @Environment(UsageStore.self) private var store
    @State private var loginSite: WebSite?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ClaudeCard(claudeAI: store.claudeAI, platform: store.platform) { site in
                        loginSite = site
                    }
                    MistralCard(state: store.mistral) { site in
                        loginSite = site
                    }
                    // OpenRouter card goes here.
                }
                .padding(16)
            }
            .refreshable { await store.refresh() }
            .navigationTitle("AI Usage")
            .toolbar {
                ToolbarItem {
                    if store.isRefreshing {
                        ProgressView()
                    } else {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await store.refresh() }
                        }
                    }
                }
                ToolbarItem {
                    Button("Accounts", systemImage: "person.crop.circle") {
                        showingSettings = true
                    }
                }
            }
        }
        .background {
            HiddenWebPages(pages: [
                store.claudeService.claudeAIPage,
                store.claudeService.platformPage,
                store.mistralService.page,
            ])
        }
        .task { await store.refresh() }
        .sheet(item: $loginSite) { site in
            WebLoginSheet(site: site) {
                Task { await store.refresh() }
            }
        }
        .sheet(isPresented: $showingSettings) {
            AccountsView()
        }
    }
}

/// Keeps the fetchers' web pages attached to a window, invisible and untouchable,
/// so WebKit runs their JavaScript at full speed. A phone-sized frame makes the
/// dashboard render its normal layout.
private struct HiddenWebPages: View {
    let pages: [WebPage]

    var body: some View {
        ZStack {
            ForEach(pages.indices, id: \.self) { index in
                WebView(pages[index])
                    .frame(width: 390, height: 844)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .environment(UsageStore())
}
