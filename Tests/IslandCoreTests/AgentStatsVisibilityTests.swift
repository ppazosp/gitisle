import Foundation
import IslandCore
import Testing

@testable import GitIsle

struct AgentStatsVisibilityTests {
  @Test func enabledProvidersDefaultToAllAndPersistSelectedHarnesses() throws {
    let allProviders = Set(AgentProvider.allCases)
    #expect(AppSettings().enabledUsageProviders == allProviders)

    let legacy = try JSONDecoder().decode(
      AppSettings.self,
      from: Data(#"{"codexHome":"/legacy/codex","claudeHome":"/legacy/claude"}"#.utf8))
    #expect(legacy.enabledUsageProviders == allProviders)

    var configured = legacy
    configured.enabledUsageProviders = [.pi]
    let encoded = try JSONEncoder().encode(configured)
    let restored = try JSONDecoder().decode(AppSettings.self, from: encoded)
    #expect(restored.enabledUsageProviders == [.pi])
  }

  @Test @MainActor func disablingHarnessHidesAndDropsExistingUsage() {
    let store = IslandStore(demo: true)
    store.usage[.pi] = [
      UsageSummary(
        provider: .pi, days: 1, tokens: 42, inputTokens: 30, outputTokens: 12,
        cachedTokens: 0, cacheCreationTokens: 0, estimatedCost: nil, models: [], partial: false,
        updatedAt: Date())
    ]

    store.update { $0.enabledUsageProviders.remove(.pi) }

    #expect(!store.visibleUsageProviders.contains(.pi))
    #expect(store.usage[.pi] == nil)
  }

}
