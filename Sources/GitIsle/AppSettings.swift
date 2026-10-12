import Foundation

enum ChartStyle: String, Codable, CaseIterable {
  case bars, line, area, cumulative

  var label: String { rawValue.capitalized }
  var symbol: String {
    switch self {
    case .bars: "chart.bar.fill"
    case .line: "chart.xyaxis.line"
    case .area: "chart.line.uptrend.xyaxis"
    case .cumulative: "sum"
    }
  }
}

enum UsageMetric: String, Codable, CaseIterable {
  case tokens, cost
  var label: String { self == .tokens ? "Tokens" : "Cost" }
}

enum CostCurrency: String, Codable, CaseIterable {
  case usd, eur
  var code: String { rawValue.uppercased() }
}

struct AppSettings: Codable, Equatable {
  var repositories = ""
  var hoverDelay = 0.2
  /// How often to look for new PRs and refresh the quiet ones.
  var githubRefreshSeconds = 60.0
  /// How often to refresh active PRs: checks running, merging, or just updated.
  var activeRefreshSeconds = 10.0
  var displayID: UInt32?
  var showInFullscreen = false
  var notificationsEnabled = false
  var codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
  var claudeHome =
    ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"
  /// Island banners for changes, separate from system notifications.
  var bannersEnabled = true
  var notificationSound = true
  /// Which changes announce themselves, by `PRStatus` raw value.
  var announcedKinds: Set<String> = ["merged", "failed", "review", "queued"]
  /// Costs are recorded in US dollars; euros use `usdToEur`, which the person sets.
  var currency: CostCurrency = .usd
  var usdToEur = 0.86
  var githubChart: ChartStyle = .bars
  var usageChart: ChartStyle = .bars
  var usageMetric: UsageMetric = .tokens
  /// First-run setup has been finished or skipped.
  var onboardingCompleted = false

  init() {}

  /// Missing keys keep their defaults, so adding a setting never resets the others.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = AppSettings()
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    repositories = value(.repositories, defaults.repositories)
    hoverDelay = value(.hoverDelay, defaults.hoverDelay)
    githubRefreshSeconds = value(.githubRefreshSeconds, defaults.githubRefreshSeconds)
    activeRefreshSeconds = value(.activeRefreshSeconds, defaults.activeRefreshSeconds)
    displayID = value(.displayID, defaults.displayID)
    showInFullscreen = value(.showInFullscreen, defaults.showInFullscreen)
    notificationsEnabled = value(.notificationsEnabled, defaults.notificationsEnabled)
    codexHome = value(.codexHome, defaults.codexHome)
    claudeHome = value(.claudeHome, defaults.claudeHome)
    bannersEnabled = value(.bannersEnabled, defaults.bannersEnabled)
    notificationSound = value(.notificationSound, defaults.notificationSound)
    announcedKinds = value(.announcedKinds, defaults.announcedKinds)
    currency = value(.currency, defaults.currency)
    usdToEur = value(.usdToEur, defaults.usdToEur)
    githubChart = value(.githubChart, defaults.githubChart)
    usageChart = value(.usageChart, defaults.usageChart)
    usageMetric = value(.usageMetric, defaults.usageMetric)
    // Settings saved before onboarding existed belong to someone already set up.
    onboardingCompleted = value(.onboardingCompleted, true)
  }

  static func load(from url: URL) -> AppSettings {
    guard let data = try? Data(contentsOf: url),
      let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
    else {
      return AppSettings()
    }
    return settings
  }

  func save(to url: URL) throws {
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }

  /// Formats a cost recorded in US dollars in the chosen currency.
  func cost(_ usd: Double?) -> String {
    guard let usd else { return "—" }
    let value = currency == .eur ? usd * usdToEur : usd
    return value.formatted(
      .currency(code: currency.code).precision(.fractionLength(value < 100 ? 2 : 0)))
  }
}

enum AppFiles {
  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("GitIsle", isDirectory: true)
  }
  static func prepare() throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }
  static var settings: URL { directory.appendingPathComponent("settings.json") }
  static var snapshot: URL { directory.appendingPathComponent("github.json") }
  static var events: URL { directory.appendingPathComponent("events.json") }
}
