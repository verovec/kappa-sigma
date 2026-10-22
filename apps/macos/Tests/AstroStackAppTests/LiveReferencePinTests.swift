import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0096's acceptance on real data, through the window model as the Tri stage drives it:
/// M31 BB+DB with `reference_breakpoint` on pauses once per lane before the registration is
/// applied; on the first lane a frame of the 2026-09-22 night is pinned, the run completes, the
/// stack records the pin, and the Studio shows the result on that frame's canvas.
@MainActor
@Suite(
  "Live reference pin — M31 broadband + dual-band, a 2026-09-22 frame pinned as reference",
  .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "120 frames of 26 MP need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(60)))
struct LiveReferencePinTests {
  @Test("two pauses, one pin on the 2026-09-22 night, the stack records it", .scratchDirectory)
  func testM31PinLive() async throws {
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
    window.add(try await Self.importRequest(captures, store: project.store))
    window.knobs.set(KnobSchema.referenceBreakpointID, to: .flag(true))
    window.select(.review)

    window.startRun(mode: .deepsky)
    let run = try #require(window.run)
    var pauses: [(lane: String, elected: Int?, pinned: Int?)] = []
    while run.isRunning {
      await ReviewPaneTests.settlePause(run)
      guard let review = run.paused else { continue }
      guard review.kind == .reference else {
        // A grading pause (the knob may be on from the project): answered as graded.
        review.continueStacking()
        continue
      }
      var pinned: Int?
      // On the first lane: a registered frame of another night than the election's, so the
      // canvas moves (the 2026-09-22 night is the dual-band lane's; the broadband lane has
      // several nights of its own).
      let electedNight = review.rows.first { $0.index == review.elected }?.night
      if pauses.isEmpty,
        let frame = review.rows.first(where: {
          $0.isRegistered && $0.index != review.elected && $0.night != electedNight
        })
      {
        review.setReference(frame.index)
        pinned = frame.index
        try LiveFrameReviewTests.capture(window, name: "live-reference-paused.png")
      }
      pauses.append((review.lane, review.elected, pinned))
      review.continueStacking()
    }
    await run.settled()

    #expect(run.phase == .finished, "\(run.journalTail.map(\.text))")
    #expect(pauses.count >= 1, "one pause per lane: \(pauses)")
    let first = try #require(pauses.first)
    let pin = try #require(first.pinned, "lane \(first.lane) has a frame of another night")
    #expect(pin != first.elected, "the anchor night's election is another frame")
    try Self.expectRecorded(project, run: run, pin: pin)
    window.select(.studio)
    try LiveFrameReviewTests.capture(window, name: "live-reference-studio.png")
  }

  /// The import as the PO's run #78 had it: the dual-band night marked by its set id.
  static func importRequest(_ captures: [String], store: ProjectStore) async throws
    -> ImportRequest
  {
    var request = ImportRequest(paths: captures)
    let scanned = try await ImportPlanning.live(store: store)(request)
    let night = try #require(
      scanned.inventory.sets.first {
        $0.key.type == .light && $0.key.session == LiveProjectRunTests.dualbandNight
      })
    request.filterSets[night.key.id] = .dualband
    return request
  }

  /// The lane, the journal, the stack record and `grades.json` all carry the pin.
  static func expectRecorded(_ project: ProjectPackage, run: RunViewModel, pin: Int) throws {
    let result = try #require(run.result)
    #expect(result.channels.allSatisfy { $0.error == nil })
    let lane = try #require(result.channels.first)
    #expect(lane.referencePin == pin && lane.reference == pin)
    let stack = try #require(try project.store.latestStack())
    let record = try StackRecord(stack: stack)
    #expect(record.referencePins?[lane.filter] == pin)
    let grades = try GradesRecord.read(from: project.url.appendingPathComponent(stack.bundlePath))
    #expect(grades.lanes.first?.pinnedReference == pin)
  }
}
