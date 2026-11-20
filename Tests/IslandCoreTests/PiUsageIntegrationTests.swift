import Foundation
import IslandCore
import Testing

@testable import GitIsle

struct PiUsageIntegrationTests {
  @Test func piHomeDefaultsFromEnvironmentAndSurvivesLegacySettingsAndPersistence() throws {
    #expect(
      AppSettings.defaultPiHome(
        environment: ["PI_CODING_AGENT_DIR": "/custom/pi-agent"],
        homeDirectory: "/home/test") == "/custom/pi-agent")
    #expect(
      AppSettings.defaultPiHome(environment: [:], homeDirectory: "/home/test")
        == "/home/test/.pi/agent")
    #expect(
      AppSettings.defaultPiHome(
        environment: ["PI_CODING_AGENT_DIR": ""], homeDirectory: "/home/test")
        == "/home/test/.pi/agent")

    let legacyData = Data(#"{"codexHome":"/legacy/codex","claudeHome":"/legacy/claude"}"#.utf8)
    let legacy = try JSONDecoder().decode(AppSettings.self, from: legacyData)
    #expect(legacy.codexHome == "/legacy/codex")
    #expect(legacy.claudeHome == "/legacy/claude")
    #expect(legacy.piHome == AppSettings.defaultPiHome())

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PiSettings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var configured = legacy
    configured.piHome = "/custom/saved-pi-agent"
    let file = directory.appendingPathComponent("settings.json")
    try configured.save(to: file)
    #expect(AppSettings.load(from: file).piHome == "/custom/saved-pi-agent")
  }

  @Test func piProviderReadsOnlyItsConfiguredHistory() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("PiUsageIntegration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let piHome = root.appendingPathComponent(".pi/agent", isDirectory: true)
    let sessionDirectory = piHome.appendingPathComponent("sessions/project", isDirectory: true)
    try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

    let now = Date()
    let formatter = ISO8601DateFormatter()
    let recent = formatter.string(from: now)
    let older = formatter.string(from: now.addingTimeInterval(-3 * 86_400))
    let fixture =
      [
        #"{"type":"session","version":3,"id":"synthetic-session","timestamp":"\#(recent)"}"#,
        #"{"type":"message","timestamp":"\#(recent)","message":{"role":"assistant","provider":"openai-codex","model":"openai/gpt-5.4","timestamp":\#(Int(now.timeIntervalSince1970 * 1000)),"usage":{"input":10,"output":4,"cacheRead":6,"cacheWrite":2,"totalTokens":22}}}"#,
        #"{"type":"message","timestamp":"\#(older)","message":{"role":"assistant","provider":"openai-codex","model":"openai/gpt-5.4","timestamp":\#(Int(now.addingTimeInterval(-3 * 86_400).timeIntervalSince1970 * 1000)),"usage":{"input":7,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":8}}}"#,
      ].joined(separator: "\n") + "\n"
    try fixture.write(
      to: sessionDirectory.appendingPathComponent("synthetic-session.jsonl"),
      atomically: true, encoding: .utf8)

    let provider = AgentProvider.pi

    let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    let service = UsageService(cacheRoot: cacheRoot)
    let testEnvironment = ["HOME": root.path]
    let pi = try await service.summaries(
      provider: provider,
      codexHome: root.appendingPathComponent("empty-codex").path,
      claudeHome: root.appendingPathComponent("empty-claude").path,
      piHome: piHome.path,
      environment: testEnvironment)
    let codex = try await service.summaries(
      provider: .codex,
      codexHome: root.appendingPathComponent("empty-codex").path,
      claudeHome: root.appendingPathComponent("empty-claude").path,
      piHome: piHome.path,
      environment: testEnvironment)
    #expect(pi.map(\.days) == [1, 7, 30])
    #expect(pi.allSatisfy { $0.provider == .pi })
    let today = try #require(pi.first { $0.days == 1 })
    let week = try #require(pi.first { $0.days == 7 })
    let month = try #require(pi.first { $0.days == 30 })
    #expect(today.tokens == 22)
    #expect(today.cachedTokens == 6)
    #expect(today.estimatedCost ?? 0 > 0)
    #expect(!today.daily.isEmpty)
    #expect(!today.dailyCost.isEmpty)
    #expect(today.models.map(\.name) == ["gpt-5.4"])
    #expect(week.tokens == 30)
    #expect(month.tokens == 30)
    #expect(!today.partial)
    #expect(!week.partial)
    #expect(!month.partial)
    #expect(codex.allSatisfy { $0.tokens == 0 })

    let sessionFile = sessionDirectory.appendingPathComponent("synthetic-session.jsonl")
    let handle = try FileHandle(forWritingTo: sessionFile)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("not-json\n".utf8))
    try handle.close()

    let partialPi = try await service.summaries(
      provider: provider,
      codexHome: root.appendingPathComponent("empty-codex").path,
      claudeHome: root.appendingPathComponent("empty-claude").path,
      piHome: piHome.path,
      environment: testEnvironment)
    #expect(try #require(partialPi.first { $0.days == 1 }).tokens == 22)
    #expect(partialPi.allSatisfy { $0.partial })
  }
}
