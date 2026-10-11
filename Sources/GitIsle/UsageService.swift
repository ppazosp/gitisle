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
    return [1, 7, 30].map { window in
      let summary = snapshot.summary(forLastDays: window)
      let calendar = Calendar.current
      let start = calendar.date(
        byAdding: .day, value: -(window - 1), to: calendar.startOfDay(for: snapshot.updatedAt))!
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.calendar = calendar
      let firstDay = formatter.string(from: start)
      let days = snapshot.daily.filter { $0.date >= firstDay }
      let sortedDays = days.sorted { $0.date < $1.date }
      let daily = sortedDays.map { DailyValue(day: $0.date, value: Double($0.totalTokens ?? 0)) }
      let dailyCost = sortedDays.map { DailyValue(day: $0.date, value: $0.costUSD ?? 0) }
      // A window with no records is zero usage, not unknown usage (for example just after midnight).
      let empty = summary.entryCount == 0
      let rows = days.flatMap { $0.modelBreakdowns ?? [] }
      let grouped = Dictionary(grouping: rows, by: \.modelName)
      let models = grouped.map { name, values in
        UsageModel(
          name: name, tokens: UsageMath.tokens(values.map(\.totalTokens)),
          estimatedCost: UsageMath.costs(values.map(\.costUSD)))
      }.sorted { ($0.tokens ?? 0) > ($1.tokens ?? 0) }
      return UsageSummary(
        provider: provider, days: window, tokens: empty ? 0 : summary.totalTokens,
        inputTokens: empty ? 0 : summary.tokenMix.inputTokens,
        outputTokens: empty ? 0 : summary.tokenMix.outputTokens,
        cachedTokens: empty ? 0 : summary.tokenMix.cacheReadTokens,
        cacheCreationTokens: empty ? 0 : summary.tokenMix.cacheCreationTokens,
        estimatedCost: empty ? 0 : summary.totalCostUSD, models: models, daily: daily,
        dailyCost: dailyCost,
        partial: snapshot.historyScanIsPartial || !snapshot.historyCoverageIsEstablished
          || summary.incompleteRequestCount > 0
          || summary.coverage.unpriced > 0,
        updatedAt: snapshot.updatedAt)
    }
  }
}
