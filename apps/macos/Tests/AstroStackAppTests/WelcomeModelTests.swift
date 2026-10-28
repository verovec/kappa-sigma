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

    #expect(model.catalog.entries.map(\.target) == ["IC 1848", "M 31"])
    #expect(model.catalog.entries.map(\.summary?.sources) == [0, 2])
    #expect(model.catalog.entries.map(\.url) == [ic1848, m31])
  }

  @Test("a recent project that cannot be read is listed without counts", .scratchDirectory)
  func testUnreadableProjectHasNoSummary() async throws {
    let broken = try ScratchDirectory.url.appendingPathComponent("Broken.astrostack")
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("not sqlite".utf8).write(to: broken.appendingPathComponent("project.db"))

    let model = WelcomeModel(recentURLs: { [broken] }, tools: Self.noTools)
    await model.reload()

    #expect(model.catalog.entries.map(\.target) == ["Broken"])
    #expect(model.catalog.entries.first?.summary == nil)
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

  @Test("each unusable tool gets one install card in the state it was found in")
  func testInstallCards() async {
    let model = WelcomeModel(recentURLs: { [] }, tools: WelcomeViewTests.mixedTools)

    await model.recheckTools()

    #expect(model.cards[.siril]?.state == .found(URL(fileURLWithPath: "/Applications/Siril.app")))
    #expect(model.cards[.graxpert]?.state == .missing)
    #expect(model.cards[.starnet]?.state == .outdated(version: "1.0"))
  }

  @Test("an install card's re-check reports what the tool is now, an old one staying outdated")
  func testCheck() async {
    let tools = WelcomeViewTests.mixedTools
    let siril = URL(fileURLWithPath: "/Applications/Siril.app")
    #expect(await WelcomeModel.check(.siril, tools)() == .found(siril))
    #expect(await WelcomeModel.check(.graxpert, tools)() == .missing)
    #expect(await WelcomeModel.check(.starnet, tools)() == .outdated(version: "1.0"))
  }

  @Test("a second check updates the cards in place: a window showing one keeps it")
  func testCardsKeptAcrossChecks() async {
    let model = WelcomeModel(recentURLs: { [] }, tools: WelcomeViewTests.mixedTools)
    await model.recheckTools()
    let card = model.cards[.graxpert]

    await model.recheckTools()

    #expect(model.cards[.graxpert] === card)
  }

  @Test("an open project is found whatever the spelling of its path", .scratchDirectory)
  func testKeyResolvesSpelling() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M 31.astrostack")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

    #expect(WelcomeModel.key(url) == WelcomeModel.key(url.appendingPathComponent("")))
    #expect(WelcomeModel.key(url) == WelcomeModel.key(url.resolvingSymlinksInPath()))
  }
}
