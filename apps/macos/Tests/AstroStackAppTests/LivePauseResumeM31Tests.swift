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
/// lane, the project reopened, Continue — the lanes done are reused byte for byte, the lanes left
/// hold the uninterrupted run's pixels exactly. Wall times go to the attachment
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
    let ours = paused.output
    // The masters the paused part wrote, by checksum: Continue must reuse them as they are.
    let kept = try Dictionary(
      uniqueKeysWithValues: checkpoint.lanesDone.map { lane in
        (lane, try FinishOracle.sha256(of: ours.appendingPathComponent("master_\(lane).fits")))
      })

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
    let (deltas, laneLines) = try Self.verify(
      resumed, checkpoint: checkpoint, kept: kept, ours: ours,
      reference: project.url.appendingPathComponent("stacks/\(straight.runID)"))
    let report: [String: Any] = [
      "seconds": timings, "lanes_done": checkpoint.lanesDone, "lanes_left": checkpoint.lanesLeft,
      "max_abs_delta_vs_uninterrupted": deltas, "lane_lines": laneLines,
      "stacked_uninterrupted": Self.stacked(straight), "stacked_continued": Self.stacked(resumed),
    ]
    Attachment.record(
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
      named: "pause-resume-m31.json")
  }

  /// The lanes done reused byte for byte (`kept`: their checksums at the pause), the lanes left
  /// pixel-identical to `reference`; returns every master's max |Δ| against `reference` and the
  /// journal's reuse lines.
  static func verify(
    _ resumed: RunViewModel, checkpoint: PreprocessCheckpoint, kept: [String: String], ours: URL,
    reference: URL
  ) throws -> ([String: Double], [String]) {
    // The step titles, not the journal: it keeps the last lines only, and Siril's thousands of
    // the lanes left push the early « reusing » line out.
    let laneLines = resumed.steps.map(\.title).filter {
      $0.hasPrefix("reusing ") || $0.hasPrefix("grading + stacking ")
    }
    for (lane, sha) in kept {
      #expect(
        laneLines.contains { $0.hasPrefix("reusing ") && $0.hasSuffix(" \(lane)") }, "\(laneLines)")
      let after = try FinishOracle.sha256(of: ours.appendingPathComponent("master_\(lane).fits"))
      #expect(after == sha, "master_\(lane) was stacked again")
    }
    var deltas: [String: Double] = [:]
    for lane in checkpoint.lanesLeft {
      let delta = try Self.maxDelta("master_\(lane).fits", ours, reference)
      #expect(delta == 0, "master_\(lane) stacked after Continue differs: max |Δ| \(delta)")
      deltas["master_\(lane).fits"] = delta
    }
    // Two independent stackings of a done lane (the uninterrupted run's, the paused run's):
    // measured, not asserted — what Siril's star matching moves run to run.
    for lane in checkpoint.lanesDone {
      deltas["master_\(lane).fits"] = try Self.maxDelta("master_\(lane).fits", ours, reference)
    }
    // The continued run's bundle names the same layers, in the same order, each file present.
    let layers = (resumed.result?.bundle?.layers ?? []).map(\.file)
    let expected = try BundleWriter.read(from: reference).layers.map(\.file)
    #expect(!layers.isEmpty && layers == expected)
    for file in layers {
      #expect(FileManager.default.fileExists(atPath: ours.appendingPathComponent(file).path))
    }
    return (deltas, laneLines)
  }

  /// Each channel's stacked frames, « RGB 110/120 ».
  static func stacked(_ run: RunViewModel) -> [String] {
    (run.result?.channels ?? []).map { "\($0.filter) \($0.stackedFrames)/\($0.inputFrames)" }
  }

  /// The largest |Δ| between `file` in `ours` and in `reference`; infinity when the geometry
  /// differs or a pixel is NaN on one side only (NaN on both counts as equal).
  static func maxDelta(_ file: String, _ ours: URL, _ reference: URL) throws -> Double {
    let lhs = try FITSFile.read(at: ours.appendingPathComponent(file)).image()
    let rhs = try FITSFile.read(at: reference.appendingPathComponent(file)).image()
    guard (lhs.width, lhs.height, lhs.planes.count) == (rhs.width, rhs.height, rhs.planes.count)
    else { return .infinity }
    var delta = 0.0
    for (left, right) in zip(lhs.planes, rhs.planes) {
      for index in left.indices where left[index] != right[index] {
        guard !left[index].isNaN, !right[index].isNaN else {
          if left[index].isNaN != right[index].isNaN { return .infinity }
          continue
        }
        delta = max(delta, Double(abs(left[index] - right[index])))
      }
    }
    return delta
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
