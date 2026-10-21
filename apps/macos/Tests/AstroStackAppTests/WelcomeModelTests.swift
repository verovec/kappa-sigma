import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

@MainActor
@Suite("WelcomeModel: recent projects and host tools as the welcome window shows them")
struct WelcomeModelTests {
  static let noTools = HostTools { .missing(path: "/nowhere/\($0.rawValue)") }

  @Test("recent projects keep their order and counts; a deleted one is dropped", .scratchDirectory)
  func testRecentProjectsSummary() async throws {
    let folder = try ScratchDirectory.url
    let m31 = try NewProject.create(target: "M 31", in: folder)
    let ic1848 = try NewProject.create(target: "IC 1848", in: folder)
    let package = try ProjectPackage.open(at: m31)
    _ = try package.store.addSource(kind: .night, path: "/captures/M31/2026-09-22")
    _ = try package.store.addSource(kind: .night, path: "/captures/M31/2026-10-18")
    try package.close()
    let gone = folder.appendingPathComponent("Gone.astrostack")

    let model = WelcomeModel(recentURLs: { [ic1848, gone, m31] }, tools: Self.noTools)
    await model.reload()

    #expect(model.recent.map(\.target) == ["IC 1848", "M 31"])
    #expect(model.recent.map(\.summary?.sources) == [0, 2])
    #expect(model.recent.map(\.url) == [ic1848, m31])
  }

  @Test("a recent project that cannot be read is listed without counts", .scratchDirectory)
  func testUnreadableProjectHasNoSummary() async throws {
    let broken = try ScratchDirectory.url.appendingPathComponent("Broken.astrostack")
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("not sqlite".utf8).write(to: broken.appendingPathComponent("project.db"))

    let model = WelcomeModel(recentURLs: { [broken] }, tools: Self.noTools)
    await model.reload()

    #expect(model.recent.map(\.target) == ["Broken"])
    #expect(model.recent.first?.summary == nil)
  }

  @Test("each tool's status comes from the host-tool client, in the catalogue's order")
  func testToolStatuses() async {
    let tools = HostTools { tool in
      tool == .siril ? .found(path: "/siril", version: "1.4.4") : .missing(path: "/x")
    }
    let model = WelcomeModel(recentURLs: { [] }, tools: tools)
    #expect(model.tools.isEmpty)

    await model.recheckTools()

    #expect(model.tools.map(\.tool) == HostTool.allCases)
    #expect(model.tools.first?.status == .found(path: "/siril", version: "1.4.4"))
    #expect(model.tools.dropFirst().allSatisfy { !$0.status.isUsable })
  }

  @Test(
    "a project open in a document is counted by that document, never reopened from disk",
    .scratchDirectory)
  func testOpenProjectIsNotReopened() async throws {
    // Not SQLite: reading it from disk would give no counts.
    let open = try ScratchDirectory.url.appendingPathComponent("M 31.astrostack")
    try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
    try Data("not sqlite".utf8).write(to: open.appendingPathComponent("project.db"))
    let counted = ProjectSummary(sources: 3, stacks: 1)

    let model = WelcomeModel(
      recentURLs: { [open] }, tools: Self.noTools,
      openProjects: { [open.standardizedFileURL: counted] })
    await model.reload()

    #expect(model.recent.first?.summary == counted)
  }

  @Test("each unusable tool gets one install card in the state it was found in")
  func testInstallCards() async {
    let model = WelcomeModel(recentURLs: { [] }, tools: WelcomeViewTests.mixedTools)

    await model.recheckTools()

    #expect(model.cards[.siril]?.state == .found(URL(fileURLWithPath: "/Applications/Siril.app")))
    #expect(model.cards[.graxpert]?.state == .missing)
    #expect(model.cards[.starnet]?.state == .outdated(version: "1.0"))
  }

  @Test("an install card's re-check reports the tool's path only once it is usable")
  func testLocator() async {
    let tools = WelcomeViewTests.mixedTools
    #expect(await WelcomeModel.locator(.siril, tools)()?.path == "/Applications/Siril.app")
    #expect(await WelcomeModel.locator(.graxpert, tools)() == nil)
    #expect(await WelcomeModel.locator(.starnet, tools)() == nil)
  }
}
