import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Tri stage through a run (card 0069): the pane lays out over a paused lane and over the
/// finished run, in fr and en; Continue resumes the run; the stack records the decisions and
/// Tri reads « done ».
@MainActor
@Suite("Review pane — paused and finished runs lay out; decisions reach the stack record")
struct ReviewPaneTests {
  /// A run that pauses on lane L with four graded frames, then finishes as `RunPanelTests` does.
  nonisolated static func pausingRun(thumbnails: URL, seen: Recorded<PreprocessRequest>)
    -> RunServices.Run
  {
    { request in
      seen.append(request)
      return AsyncThrowingStream(PreprocessEvent.self) { continuation in
        let task = Task {
          continuation.yield(
            .progress(
              .init(step: 2, steps: 5, title: "grading + stacking M31 L", percent: nil, line: "")))
          let frames = Self.frames(thumbnails: thumbnails)
          continuation.yield(.frames(frames))
          do {
            let decision = try await frames.gate.decision()
            continuation.yield(.finished(try Self.finished(request, frames, decision)))
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
  }

  /// The view-model fixture's frames, thumbnails pointed at `folder`.
  nonisolated static func frames(thumbnails folder: URL) -> PreprocessEvent.Frames {
    var frames = FrameReviewViewModelTests.frames()
    frames.thumbnails = frames.thumbnails.map { thumbnail in
      thumbnail.map { folder.appendingPathComponent(($0 as NSString).lastPathComponent).path }
    }
    return frames
  }

  /// The finished result with lane L's grades as the stacker leaves them: the decision applied,
  /// the grader's reason kept as provenance.
  nonisolated static func finished(
    _ request: PreprocessRequest, _ frames: PreprocessEvent.Frames, _ decision: FrameDecision
  ) throws -> PreprocessResult {
    var result = try RunPanelTests.finished(request)
    result.channels[0].frameDecision = decision
    var outcome = ChannelGrading.Outcome(
      grades: frames.grades, rejectedRegistered: [], registeredCount: 0)
    ChannelGrading.apply(decision, to: &outcome)
    let grades = outcome.grades
    result.channels[0].grades = grades
    return result
  }

  /// A 2×2 PNG per thumbnail path the frames name.
  static func thumbnails() throws -> URL {
    let folder = try ScratchDirectory.url.appendingPathComponent("thumbs", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
      NSColor.gray.setFill()
      rect.fill()
      return true
    }
    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(
      NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    for name in ["1.png", "2.png", "3.png"] {
      try png.write(to: folder.appendingPathComponent(name))
    }
    return folder
  }

  /// Returns once the run pauses at a review, or stops: observation of `paused` and `phase`, no
  /// sleep, no polling (the stream is reduced on the main actor, as these reads are).
  static func settlePause(_ run: RunViewModel) async {
    while run.paused == nil && run.isRunning {
      await withCheckedContinuation { continuation in
        withObservationTracking {
          _ = run.paused
          _ = run.phase
        } onChange: {
          continuation.resume()
        }
      }
    }
  }

  @Test(
    "a paused lane lays out with its table and blink, Continue resumes, the stack records it",
    .scratchDirectory, arguments: ["en", "fr"])
  func testPausedThenFinished(_ language: String) async throws {
    let ran = Recorded<PreprocessRequest>()
    let fixture = try ProjectTests.fixture(
      run: Self.pausingRun(thumbnails: try Self.thumbnails(), seen: ran))
    defer { try? fixture.project.close() }
    let window = fixture.window
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.knobs.set(KnobSchema.frameReviewID, to: .flag(true))
    window.startRun()
    let run = try #require(window.run)
    await Self.settlePause(run)
    let review = try #require(run.paused)
    #expect(review.lane == "L" && review.isLive && review.current == 1)
    #expect(ran.all.first?.settings.frameReview == true, "the knob reaches the run")
    window.select(.review)
    #expect(window.reviewLanes.first === review)

    let host = ImportSheetTests.host(
      ProjectWindowView(model: window).environment(\.locale, Locale(identifier: language))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640 && host.fittingSize.height >= 400)
    host.sizingOptions = [.minSize]
    host.layoutSubtreeIfNeeded()
    if language == "en" { try RunPanelTests.attach(host, "review-paused.png") }

    review.reject(1)
    review.keep(2)
    review.continueStacking()
    #expect(review.isAnswered && run.answered.first === review, "shown until the result lands")
    await run.settled()
    #expect(run.phase == .finished && run.paused == nil)
    #expect(run.decisions == ["L": FrameDecision(exclude: [1], forceKeep: [2])])
    let stack = try #require(try fixture.project.store.latestStack())
    let record = try StackRecord(stack: stack)
    #expect(record.frameReview == ["L": FrameDecision(exclude: [1], forceKeep: [2])])
    #expect(window.statuses[.review] == .done)

    // The finished run shows read-only: the lanes of its result, verdicts as stacked.
    let lanes = window.reviewLanes
    #expect(lanes.map(\.lane) == ["RGB", "Ha"] && lanes.allSatisfy { !$0.isLive })
    #expect(lanes[0].rows.map(\.isKept) == [false, true, true, false])
    window.refresh()
    #expect(
      window.reviewLanes.first === lanes.first, "read-only lanes are built once, not per render")
    host.layoutSubtreeIfNeeded()
    if language == "en" { try RunPanelTests.attach(host, "review-finished.png") }
  }

  @Test(
    "a project without a run shows the empty state; the knob toggle is the panel's knob",
    .scratchDirectory)
  func testEmptyAndToggle() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      planning: { _ in ImportPlanningStub.empty })
    #expect(window.reviewLanes.isEmpty)
    window.select(.review)
    let host = ImportSheetTests.host(
      ProjectWindowView(model: window).environment(\.locale, Locale(identifier: "fr")))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640)
    window.knobs.set(KnobSchema.frameReviewID, to: .flag(true))
    #expect(window.knobs.patch == KnobPatch(values: [KnobSchema.frameReviewID: .flag(true)]))
  }

  @Test(
    "cancelling a run that waits at the review drops the lane: nothing left to answer",
    .scratchDirectory)
  func testCancelWhilePausedDropsTheLane() async throws {
    let ran = Recorded<PreprocessRequest>()
    let fixture = try ProjectTests.fixture(
      run: Self.pausingRun(thumbnails: try Self.thumbnails(), seen: ran))
    defer { try? fixture.project.close() }
    let window = fixture.window
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.knobs.set(KnobSchema.frameReviewID, to: .flag(true))
    window.startRun()
    let run = try #require(window.run)
    await Self.settlePause(run)
    let review = try #require(run.paused)
    window.cancelRun()
    await run.settled()
    #expect(run.phase == .cancelled && run.paused == nil && run.answered.isEmpty)
    #expect(window.reviewLanes.isEmpty, "no stack, no run result: nothing to show")
    review.continueStacking()
    #expect(run.decisions.isEmpty, "a dead lane's Continue records nothing")
  }
}
