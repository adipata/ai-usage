import Foundation
import Observation

/// App-wide state: the last known usage of every source, cached between launches.
@Observable
final class UsageStore {
    var claudeAI: SourceState<ClaudeAIUsage>
    var platform: SourceState<PlatformUsage>
    var mistral: SourceState<MistralUsage>
    private(set) var isRefreshing = false

    let claudeService = ClaudeWebService()
    let mistralService = MistralWebService()

    var rawResponses: [String: String] {
        var all = claudeService.lastRaw
        all["mistral subscription"] = mistralService.lastRaw
        return all
    }

    private static let claudeAIKey = "cache.claudeAI"
    private static let platformKey = "cache.platform"
    private static let mistralKey = "cache.mistral"

    init() {
        claudeAI = Self.load(Self.claudeAIKey) ?? SourceState()
        platform = Self.load(Self.platformKey) ?? SourceState()
        mistral = Self.load(Self.mistralKey) ?? SourceState()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshClaudeAI()
        await refreshPlatform()
        await refreshMistral()
    }

    /// Refetches when the data is older than 15 minutes or a reset time has passed
    /// (otherwise a countdown would sit at "now"). Called when the app comes to the foreground.
    func refreshIfStale(now: Date = .now) async {
        let fetches: [Date?] = [claudeAI.fetchedAt, platform.fetchedAt, mistral.fetchedAt]
        let fetched: [Date] = fetches.compactMap { $0 }
        guard fetched.count == fetches.count, let oldest = fetched.min() else {
            await refresh()
            return
        }

        var resets: [Date] = []
        if let usage = claudeAI.value {
            if let reset = usage.weekly?.resetsAt { resets.append(reset) }
            resets.append(contentsOf: usage.modelLimits.compactMap { $0.resetsAt })
        }
        if let usage = mistral.value {
            resets.append(contentsOf: usage.allowances.compactMap { $0.resetsAt })
        }

        let isOld = now.timeIntervalSince(oldest) > 15 * 60
        if isOld || resets.contains(where: { $0 <= now }) {
            await refresh()
        }
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

    func refreshMistral() async {
        do {
            mistral = SourceState(value: try await mistralService.fetchUsage(), fetchedAt: .now)
        } catch {
            mistral.error = error.localizedDescription
            mistral.needsSignIn = FetchError.isNotSignedIn(error)
        }
        Self.save(mistral, Self.mistralKey)
    }

    func signOut(_ site: WebSite) async {
        await site.signOut()
        switch site {
        case .claudeAI: claudeAI = SourceState(needsSignIn: true)
        case .claudePlatform: platform = SourceState(needsSignIn: true)
        case .mistral: mistral = SourceState(needsSignIn: true)
        }
        Self.save(claudeAI, Self.claudeAIKey)
        Self.save(platform, Self.platformKey)
        Self.save(mistral, Self.mistralKey)
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
