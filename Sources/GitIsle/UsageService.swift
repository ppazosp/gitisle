import CodexBarCore
import Foundation
import IslandCore

actor UsageService {
  private let fetcher: CostUsageFetcher
  init(cacheRoot: URL) { fetcher = CostUsageFetcher(cacheRoot: cacheRoot) }

  func summaries(provider: AgentProvider, codexHome: String, claudeHome: String) async throws
    -> [UsageSummary]
  {
    var environment = ProcessInfo.processInfo.environment
    environment["CODEX_HOME"] = codexHome
    environment["CLAUDE_CONFIG_DIR"] = claudeHome
    let snapshot = try await fetcher.loadTokenSnapshot(
      provider: provider == .codex ? .codex : .claude, environment: environment,
      codexHomePath: codexHome, historyDays: 30, allowPricingRefresh: false,
      includePiSessions: false
    )
    return [1, 7, 30].map { days in
      let summary = snapshot.summary(forLastDays: days)
      let calendar = Calendar.current
      let start = calendar.date(
        byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: snapshot.updatedAt))!
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.calendar = calendar
      let firstDay = formatter.string(from: start)
      let rows = snapshot.daily.filter { $0.date >= firstDay }.flatMap { $0.modelBreakdowns ?? [] }
      let grouped = Dictionary(grouping: rows, by: \.modelName)
      let models = grouped.map { name, values in
        UsageModel(
          name: name, tokens: UsageMath.tokens(values.map(\.totalTokens)),
          estimatedCost: UsageMath.costs(values.map(\.costUSD)))
      }.sorted { ($0.tokens ?? 0) > ($1.tokens ?? 0) }
      return UsageSummary(
        provider: provider, days: days, tokens: summary.totalTokens,
        inputTokens: summary.tokenMix.inputTokens, outputTokens: summary.tokenMix.outputTokens,
        cachedTokens: summary.tokenMix.cacheReadTokens,
        cacheCreationTokens: summary.tokenMix.cacheCreationTokens,
        estimatedCost: summary.totalCostUSD, models: models,
        partial: snapshot.historyScanIsPartial || !snapshot.historyCoverageIsEstablished
          || summary.incompleteRequestCount > 0
          || summary.coverage.unpriced > 0,
        updatedAt: snapshot.updatedAt)
    }
  }
}
