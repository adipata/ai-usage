import SwiftUI

@main struct MyApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
