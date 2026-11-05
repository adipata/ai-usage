import Foundation
import Observation

/// App-wide state: the last known usage of every source, cached between launches.
@Observable
final class UsageStore {
    var claudeAI: SourceState<ClaudeAIUsage>
    var platform: SourceState<PlatformUsage>
    private(set) var isRefreshing = false

    let claudeService = ClaudeWebService()

    var rawResponses: [String: String] { claudeService.lastRaw }

    private static let claudeAIKey = "cache.claudeAI"
    private static let platformKey = "cache.platform"

    init() {
        claudeAI = Self.load(Self.claudeAIKey) ?? SourceState()
        platform = Self.load(Self.platformKey) ?? SourceState()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshClaudeAI()
        await refreshPlatform()
    }

    func refreshClaudeAI() async {
        do {
            claudeAI = SourceState(value: try await claudeService.fetchClaudeAIUsage(), fetchedAt: .now)
        } catch {
            claudeAI.error = error.localizedDescription
            claudeAI.needsSignIn = FetchError.isNotSignedIn(error)
        }
        Self.save(claudeAI, Self.claudeAIKey)
    }

    func refreshPlatform() async {
        do {
            platform = SourceState(value: try await claudeService.fetchPlatformUsage(), fetchedAt: .now)
        } catch {
            platform.error = error.localizedDescription
            platform.needsSignIn = FetchError.isNotSignedIn(error)
        }
        Self.save(platform, Self.platformKey)
    }

    func signOut(_ site: WebSite) async {
        await site.signOut()
        switch site {
        case .claudeAI: claudeAI = SourceState(needsSignIn: true)
        case .claudePlatform: platform = SourceState(needsSignIn: true)
        }
        Self.save(claudeAI, Self.claudeAIKey)
        Self.save(platform, Self.platformKey)
    }

    // MARK: Cache

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
