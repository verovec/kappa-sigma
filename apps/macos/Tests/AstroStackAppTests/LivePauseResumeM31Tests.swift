import AstroStackApp
import Foundation
import ImageKit
import Observation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0097 on the PO's real M 31 BB+DB: Continue ends on the uninterrupted run's pixels.
///
/// The dual-band night marked, as in 0058, through the window model as the Stacking stage
/// drives it: an uninterrupted run, then a run paused during its first
/// lane, the project reopened, Continue — every master and bundle layer of the continued run holds
/// the uninterrupted run's pixels exactly. Wall times go to the attachment
/// `pause-resume-m31.json` (the PR body quotes them).
@MainActor
@Suite(
  "Live pause/resume — M 31 BB+DB paused after its first lane, continued after a reopen",
  .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "full targets of 26 MP frames need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(120)))
struct LivePauseResumeM31Tests {
  @Test("Continue ends on the uninterrupted run's masters and layers", .scratchDirectory)
  func testPauseResumeM31() async throws {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("m31.astrostack"))
    defer { try? project.close() }
    let work = scratch.appendingPathComponent("work")
    var clock = Date(timeIntervalSince1970: 1_792_616_400)
    let window = Self.window(project, work: work, at: clock)
    window.add(try await Self.request(project))

    var timings: [String: Double] = [:]
    var started = Date()
    window.startRun()
    let straight = try #require(window.run)
    await straight.settled()
    timings["uninterrupted"] = Date().timeIntervalSince(started)
    #expect(straight.phase == .finished, "\(straight.journalTail.map(\.text))")

    clock += 3600
    let pausing = Self.window(project, work: work, at: clock)
    started = Date()
    pausing.startRun()
    let paused = try #require(pausing.run)
    Self.pauseInFirstLane(paused, window: pausing)
    await paused.settled()
    timings["until_paused"] = Date().timeIntervalSince(started)
    let checkpoint = try #require(paused.checkpoint, "\(paused.journalTail.map(\.text))")

    // The project closed and opened again: a fresh window over the same package.
    clock += 3600
    let reopened = Self.window(project, work: work, at: clock)
    let row = try #require(reopened.pausedRuns.first)
    started = Date()
    reopened.continueRun(row.id)
    let resumed = try #require(reopened.run)
    await resumed.settled()
    timings["continue"] = Date().timeIntervalSince(started)
    #expect(resumed.phase == .finished, "\(resumed.journalTail.map(\.text))")
    #expect(try project.store.pausedStacks().isEmpty)
    for lane in checkpoint.lanesDone {
      #expect(resumed.journal.contains { $0.text.hasPrefix("\(lane): reusing master_") })
    }
    let compared = try Self.compare(
      resumed, in: project.url.appendingPathComponent(row.bundlePath),
      with: project.url.appendingPathComponent("stacks/\(straight.runID)"))
    let report: [String: Any] = [
      "seconds": timings, "lanes_done": checkpoint.lanesDone, "lanes_left": checkpoint.lanesLeft,
      "compared": compared,
    ]
    Attachment.record(
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
      named: "pause-resume-m31.json")
  }

  /// Every master and bundle layer of `resumed` in `ours` against the same file in `reference`,
  /// pixel for pixel; returns the files compared.
  static func compare(_ resumed: RunViewModel, in ours: URL, with reference: URL) throws
    -> [String]
  {
    let layers = (resumed.result?.bundle?.layers ?? []).map(\.file)
    let masters = (resumed.result?.channels ?? []).compactMap(\.masterPath).map {
      URL(fileURLWithPath: $0).lastPathComponent
    }
    #expect(!layers.isEmpty && !masters.isEmpty)
    for file in masters + layers {
      let lhs = try FITSFile.read(at: ours.appendingPathComponent(file)).image()
      let rhs = try FITSFile.read(at: reference.appendingPathComponent(file)).image()
      #expect(lhs.planes == rhs.planes, "\(file) differs from the uninterrupted run")
    }
    return masters + layers
  }

  /// The M 31 captures with the 2026-09-22 night marked dual-band, as the PO marked it.
  static func request(_ project: ProjectPackage) async throws -> ImportRequest {
    let captures = ["M31-DB", "M31-BB"].flatMap { capture in
      ["lights", "darks", "flats", "bias"].map {
        ImportPlanning.capturesFolder.appendingPathComponent(capture).appendingPathComponent($0)
          .path
      }
    }
    guard captures.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
      try Test.cancel("captures M31-DB/M31-BB absent under ~/Documents/astro/captures")
    }
    var request = ImportRequest(paths: captures)
    let scanned = try await ImportPlanning.live(store: project.store)(request)
    let night = try #require(
      scanned.inventory.sets.first { $0.key.type == .light && $0.key.session == "2026-09-22" })
    request.filterSets[night.key.id] = .dualband
    return request
  }

  static func window(_ project: ProjectPackage, work: URL, at date: Date) -> ProjectWindowModel {
    ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      runs: RunServices(run: RunServices.live.run, now: { date }, scratch: work))
  }

  /// Presses Pause once the first lane's step is running.
  static func pauseInFirstLane(_ run: RunViewModel, window: ProjectWindowModel) {
    if run.steps.contains(where: {
      $0.state == .running && $0.title.hasPrefix("grading + stacking")
    }) {
      window.pauseRun()
      return
    }
    guard run.isRunning else { return }
    withObservationTracking {
      _ = run.steps
    } onChange: {
      Task { @MainActor in pauseInFirstLane(run, window: window) }
    }
  }
}
