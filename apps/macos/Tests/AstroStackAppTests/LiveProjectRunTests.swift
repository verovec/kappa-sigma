import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0057's acceptance on real data, through the window model as the Stacking stage drives it:
/// import M31-DB + M31-BB with the dual-band night marked (the PO's run #78 choice), run with the
/// installed Siril, and the finished run is a stack of RGB + syn_Ha + syn_OIII the Studio opens.
@MainActor
@Suite(
  "Live project run — M31 broadband + dual-band from the Stacking stage", .liveFixtures,
  .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "120 frames of 26 MP need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(60)))
struct LiveProjectRunTests {
  static let dualbandNight = "2026-09-22"

  @Test("import, run, stack registered, Studio opened on Ha + OIII + RGB", .scratchDirectory)
  func testM31RunLive() async throws {
    let captures = ["M31-DB", "M31-BB"].map {
      ImportPlanning.capturesFolder.appendingPathComponent($0).path
    }
    guard captures.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
      try Test.cancel("captures M31-DB/M31-BB absent under ~/Documents/astro/captures")
    }
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      runs: RunServices(run: RunServices.live.run, scratch: scratch.appendingPathComponent("work")))

    // The user's override, as the Import sheet records it: the dual-band night by its set id.
    var request = ImportRequest(paths: captures)
    let scanned = try await ImportPlanning.live(store: project.store)(request)
    let night = try #require(
      scanned.inventory.sets.first {
        $0.key.type == .light && $0.key.session == Self.dualbandNight
      })
    request.filterSets[night.key.id] = .dualband
    window.add(request)

    window.startRun(mode: .deepsky)
    let run = try #require(window.run)
    await run.settled()

    #expect(run.phase == .finished, "\(run.journalTail.map(\.text))")
    #expect(run.steps.allSatisfy { $0.state == .done } && !run.steps.isEmpty)
    #expect(!run.previews.isEmpty && !run.journal.isEmpty)
    let result = try #require(run.result)
    #expect(result.channels.allSatisfy { $0.error == nil })
    #expect(result.bundle?.layers.map(\.id) == ["Ha", "OIII", "RGB"])

    let stack = try #require(try project.store.stacks().first)
    #expect(stack.bundlePath == "stacks/\(run.runID)")
    #expect(try project.store.images(stackID: stack.id).map(\.role) == ["Ha", "OIII", "RGB"])
    #expect(window.selection == .studio)
    #expect(window.studio?.source.layers.map(\.id) == ["Ha", "OIII", "RGB"])
    #expect(
      !FileManager.default.fileExists(
        atPath: scratch.appendingPathComponent("work/run_\(run.runID)").path))
  }
}
