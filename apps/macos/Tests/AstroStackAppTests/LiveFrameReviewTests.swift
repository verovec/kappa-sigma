import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0069's acceptance on real data, through the window model as the Tri stage drives it:
/// M31 BB+DB with `frame_review` on pauses once per lane (broadband, then dual-band), three frames
/// are rejected by hand on the first lane, and the stack completes with three frames fewer; the
/// pane is laid out and captured while the run waits.
@MainActor
@Suite(
  "Live frame review — M31 broadband + dual-band paused per lane, three frames rejected by hand",
  .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "120 frames of 26 MP need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(60)))
struct LiveFrameReviewTests {
  static let rejectedByHand = 3

  @Test("two reviews, three rejects, the stack records them and Tri reads done", .scratchDirectory)
  func testM31ReviewLive() async throws {
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
    var request = ImportRequest(paths: captures)
    let scanned = try await ImportPlanning.live(store: project.store)(request)
    let night = try #require(
      scanned.inventory.sets.first {
        $0.key.type == .light && $0.key.session == LiveProjectRunTests.dualbandNight
      })
    request.filterSets[night.key.id] = .dualband
    window.add(request)
    window.knobs.set(KnobSchema.frameReviewID, to: .flag(true))
    window.select(.review)

    window.startRun(mode: .deepsky)
    let run = try #require(window.run)
    var reviews: [(lane: String, registered: Int, kept: Int)] = []
    while run.isRunning {
      await ReviewPaneTests.settlePause(run)
      guard let review = run.paused else { continue }
      let registered = review.rows.count(where: \.isRegistered)
      if reviews.isEmpty {
        // The first lane, by hand: the three sharpest-looking kept frames go out.
        for row in review.sortedRows.filter(\.isKept).prefix(Self.rejectedByHand) {
          review.reject(row.index)
        }
        try Self.capture(window, name: "live-review-paused.png")
      }
      reviews.append((review.lane, registered, review.keptCount))
      review.continueStacking()
    }
    await run.settled()

    #expect(run.phase == .finished, "\(run.journalTail.map(\.text))")
    #expect(reviews.count == 2, "one review per lane: \(reviews)")
    let result = try #require(run.result)
    #expect(result.channels.allSatisfy { $0.error == nil })
    let first = try #require(result.channels.first)
    #expect(first.frameDecision?.exclude.count == Self.rejectedByHand)
    #expect(
      first.grades.count { $0.rejectReason == ChannelGrading.userReason } == Self.rejectedByHand)
    #expect(first.stackedFrames == (reviews.first?.kept ?? 0))
    try Self.expectRecorded(project, window: window, result: result, first: first)
    try Self.capture(window, name: "live-review-finished.png")
  }

  /// The stack record and `grades.json` carry the two reviews; Tri reads done.
  static func expectRecorded(
    _ project: ProjectPackage, window: ProjectWindowModel, result: PreprocessResult,
    first: ChannelOutcome
  ) throws {
    let stack = try #require(try project.store.latestStack())
    let record = try StackRecord(stack: stack)
    #expect(record.frameReview?.count == 2)
    #expect(record.frameReview?[first.filter]?.exclude.count == Self.rejectedByHand)
    #expect(window.statuses[.review] == .done)
    let grades = try GradesRecord.read(from: project.url.appendingPathComponent(stack.bundlePath))
    #expect(grades.lanes.map(\.lane) == result.channels.map(\.filter))
    #expect(grades.lanes.map(\.reviewed) == [true, true])
  }

  /// The project window on the Tri stage, laid out offscreen and attached.
  static func capture(_ window: ProjectWindowModel, name: String) throws {
    let host = ImportSheetTests.host(
      ProjectWindowView(model: window, projects: .empty).environment(
        \.locale, Locale(identifier: "fr")
      )
      .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    host.sizingOptions = [.minSize]
    host.layoutSubtreeIfNeeded()
    try RunPanelTests.attach(host, name)
  }
}
