import Foundation
import Testing

@testable import IslandCore

struct DiffTests {
  @Test func linesAreNumberedFromTheirHunks() {
    let patch = """
      @@ -52,3 +52,4 @@ func load() {
         let cache = shared
      -  return read(id)
      +  if let hit = cache[id] { return hit }
      +  return read(id)
       }
      @@ -90,2 +91,2 @@
      -old
      +new
      \\ No newline at end of file
      """
    let lines = Diff.lines(patch)
    #expect(
      lines.map(\.kind) == [
        .hunk, .context, .removed, .added, .added, .context, .hunk, .removed, .added,
      ])
    #expect(
      lines[1].oldNumber == 52 && lines[1].newNumber == 52
        && lines[1].text == "  let cache = shared")
    #expect(lines[2].oldNumber == 53 && lines[2].newNumber == nil)
    #expect(lines[3].newNumber == 53 && lines[4].newNumber == 54)
    #expect(lines[5].oldNumber == 54 && lines[5].newNumber == 55 && lines[5].text == "}")
    #expect(lines[7].oldNumber == 90 && lines[8].newNumber == 91)
  }

  @Test func aTrailingNewlineIsNotALine() {
    #expect(Diff.lines("@@ -1 +1 @@\n-a\n+b\n").map(\.kind) == [.hunk, .removed, .added])
    #expect(Diff.lines("").isEmpty)
  }

  @Test func fileChangesKnowTheirKindAndFolder() {
    typealias File = PullRequestDetails.FileChange
    #expect(File.kind("ADDED") == .added && File.kind("COPIED") == .added)
    #expect(File.kind("DELETED") == .removed && File.kind("RENAMED") == .renamed)
    #expect(File.kind("CHANGED") == .modified && File.kind(nil) == .modified)
    let file = File(path: "apps/web/lib/sandbox/exec.ts", additions: 1, deletions: 0)
    #expect(file.name == "exec.ts" && file.folder == "sandbox/")
    #expect(File(path: "README.md", additions: 1, deletions: 0).folder == "")
  }

  @Test func patchesComeFromOneRESTPagePerHundredFiles() async throws {
    let body = try JSONSerialization.data(withJSONObject: [
      ["filename": "a.swift", "patch": "@@ -1 +1 @@\n-a\n+b"],
      ["filename": "image.png"],
    ])
    let paths = Paths()
    let service = GitHubService(restTransport: { path in
      await paths.add(path)
      return body
    })
    let patches = try await service.patches(repository: "example/app", number: 12, page: 2)
    #expect(patches == ["a.swift": "@@ -1 +1 @@\n-a\n+b"])
    #expect(await paths.all == ["repos/example/app/pulls/12/files?per_page=100&page=2"])
    await #expect(throws: ProcessFailure.self) {
      try await service.patches(repository: "example/app?x=1", number: 12, page: 1)
    }
  }
}

private actor Paths {
  var all: [String] = []
  func add(_ path: String) { all.append(path) }
}

struct FileTreeTests {
  private func file(_ path: String) -> PullRequestDetails.FileChange {
    .init(path: path, additions: 1, deletions: 0)
  }

  private func describe(_ rows: [FileTree.Row]) -> [String] {
    rows.map { row in
      let indent = String(repeating: "  ", count: row.depth)
      switch row.kind {
      case .folder(let name, _, let folded): return "\(indent)\(folded ? "▸" : "▾") \(name)/"
      case .file(let file): return "\(indent)\(file.name)"
      }
    }
  }

  @Test func foldersComeFirstAndSingleFolderChainsJoin() {
    let rows = FileTree.rows([
      file("README.md"),
      file("apps/omnia/app/chat/engine.ts"),
      file("apps/omnia/app/chat/recovery/held.ts"),
      file("apps/omnia/lib/sandbox/wake.ts"),
      file("apps/omnia/lib/sandbox/health.ts"),
    ])
    #expect(
      describe(rows) == [
        "▾ apps/omnia/",
        "  ▾ app/chat/",
        "    ▾ recovery/",
        "      held.ts",
        "    engine.ts",
        "  ▾ lib/sandbox/",
        "    wake.ts",
        "    health.ts",
        "README.md",
      ])
  }

  @Test func aFoldedFolderHidesWhatsInside() {
    let files = [file("apps/omnia/app/chat/engine.ts"), file("apps/omnia/lib/sandbox/wake.ts")]
    let rows = FileTree.rows(files, folded: ["apps/omnia/app/chat"])
    #expect(
      describe(rows) == ["▾ apps/omnia/", "  ▸ app/chat/", "  ▾ lib/sandbox/", "    wake.ts"])
  }
}
