import AstroStackApp
import Foundation
import RenderKit
import StackKit
import TestSupport
import Testing

/// StarNet's install card re-check (card 0108): a StarNet on disk that this Mac cannot launch is
/// « installed but cannot run », with why; only a StarNet absent from disk is « Not installed ».
@Suite("StarSeparation.check — missing, cannot run, or found")
struct StarSeparationTests {
  /// An Intel-only (x86_64) Mach-O header: what the PO's `/usr/local/bin/starnet2` is.
  static let intelHeader: [UInt8] =
    [0xCF, 0xFA, 0xED, 0xFE] + withUnsafeBytes(of: UInt32(0x0100_0007).littleEndian, Array.init)
    + [UInt8](repeating: 0, count: 24)

  /// The live client over the StarNet at `path` (when a file is there), on a Mac without Rosetta.
  static func withoutRosetta(_ path: String) -> HostTools {
    HostTools.live(
      environment: ["STARNET_BIN": path],
      probe: HostTools.Probe(
        isExecutable: { FileManager.default.fileExists(atPath: $0) }, isApp: { _ in false },
        sirilVersion: { _ in "" },
        refusal: { ExecutableCheck.refusal(path: $0, rosettaInstalled: false) }))
  }

  @Test(
    "an Intel StarNet without Rosetta is installed but cannot run, Rosetta named", .scratchDirectory
  )
  func testCheck_IntelWithoutRosetta_IsUnusable() async throws {
    let binary = try ScratchDirectory.url.appendingPathComponent("starnet2")
    try Data(Self.intelHeader).write(to: binary)

    let state = await StarSeparation.check(Self.withoutRosetta(binary.path))()

    guard case .unusable(let path, let reason) = state else {
      Issue.record("expected unusable, got \(state)")
      return
    }
    #expect(path == binary)
    #expect(reason.contains("softwareupdate --install-rosetta --agree-to-license"))
  }

  @Test("no StarNet on disk is « Not installed »")
  func testCheck_NoFile_IsMissing() async {
    let state = await StarSeparation.check(Self.withoutRosetta("/nowhere/starnet2"))()

    #expect(state == .missing)
  }

  @Test("a StarNet whose probe fails cannot run, with the probe's failure as the reason")
  func testCheck_ProbeFails_IsUnusableWithReason() async {
    let path = "/usr/local/bin/starnet2"
    let tools = HostTools { _ in .found(path: path, version: nil) }

    let state = await StarSeparation.check(tools) { _ in
      throw StarNetError.probeTimedOut(path: path)
    }()

    guard case .unusable(let url, let reason) = state else {
      Issue.record("expected unusable, got \(state)")
      return
    }
    #expect(url.path == path)
    #expect(reason.contains(path))
  }

  @Test(
    "the welcome strip shows the same verdict: an install card saying it cannot run",
    arguments: [("en", "cannot run"), ("fr", "ne peut pas")])
  @MainActor
  func testToolStrip_CannotRun(_ language: String, _ words: String) async throws {
    let path = "/usr/local/bin/starnet2"
    let tools = HostTools { tool in
      tool == .starnet
        ? .cannotRun(path: path, reason: "needs Rosetta") : .found(path: "/\(tool)", version: nil)
    }
    let model = WelcomeModel(recentURLs: { [] }, tools: tools)

    await model.recheckTools()

    let row = try #require(model.tools.first { $0.tool == .starnet })
    let card = model.cards[.starnet]?.state
    let fix = String(localized: WelcomeModel.rosettaFix())
    #expect(card == .unusable(path: URL(fileURLWithPath: path), reason: fix))
    let advice = WelcomeModel.rosettaFix().text(language)
    #expect(advice.contains(ExecutableCheck.rosettaCommand), "\(advice)")
    #expect(ToolStrip.usable(row, card: card) == nil)
    let reason = ToolStrip.reason(row).text(language)
    #expect(reason.contains(words) && reason.contains(path), "\(reason)")
  }

  @Test(
    "Separate Stars with a StarNet that cannot run shows its card as such: no step",
    .scratchDirectory)
  @MainActor
  func testSeparate_CannotRun_ShowsUnusableCard() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let tools = HostTools { _ in
      .cannotRun(path: "/usr/local/bin/starnet2", reason: "needs Rosetta")
    }
    let model = try ExportStageModelTests.model(
      opened, studio: studio, services: try ExportStageModelTests.services(tools))

    await model.separateStars()

    #expect(
      model.installCard?.state
        == .unusable(
          path: URL(fileURLWithPath: "/usr/local/bin/starnet2"),
          reason: String(localized: WelcomeModel.rosettaFix())))
    #expect(model.failure == nil)
    #expect(studio.steps.map(\.processID) == ["channel-combination"])
  }
}
