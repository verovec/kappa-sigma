import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Pause, Continue and Discard of a preprocessing run (card 0097): Pause asks the run to stop
/// after its lane; the paused run is a `paused` stack row that survives closing the project;
/// Continue resumes the same run in the same folder and completes that row; Discard deletes the
/// row and the run's folder.
@MainActor
@Suite("Run pause — Pause, Continue and Discard of a paused run")
struct RunPauseTests {
  nonisolated static let checkpoint = PreprocessCheckpoint(
    runID: ProjectTests.runID, lanesDone: ["RGB"], lanesLeft: ["RGB-dualband"])

  /// A run that writes its first lane's master, waits for `release`, then pauses when its gate
  /// was requested — or, resuming, writes the bundle and finishes.
  static func pausingRun(
    _ seen: Recorded<PreprocessRequest>, started: AsyncStream<Void>.Continuation,
    release: AsyncStream<Void>, pausesAgain: Bool = false
  ) -> RunServices.Run {
    let finish = ProjectTests.fakeRun(Recorded<PreprocessRequest>())
    return { request in
      seen.append(request)
      if request.resuming && !pausesAgain { return finish(request) }
      return AsyncThrowingStream(PreprocessEvent.self) { continuation in
        let task = Task {
          do {
            try FileManager.default.createDirectory(
              at: request.output, withIntermediateDirectories: true)
            FileManager.default.createFile(
              atPath: request.output.appendingPathComponent("master_RGB.fits").path, contents: nil)
            continuation.yield(
              .progress(
                .init(
                  step: 2, steps: 6, title: "grading + stacking M31 RGB", percent: nil,
                  line: "")))
            started.yield()
            for await _ in release { break }
            guard request.pause?.isRequested == true else {
              throw CancellationError()
            }
            continuation.yield(.paused(checkpoint))
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
  }

  struct Harness {
    var fixture: ProjectTests.Fixture
    var seen: Recorded<PreprocessRequest>
    var started: AsyncStream<Void>
    var release: AsyncStream<Void>.Continuation
  }

  static func harness() throws -> Harness {
    let seen = Recorded<PreprocessRequest>()
    let (started, starting) = AsyncStream.makeStream(of: Void.self)
    let (release, releasing) = AsyncStream.makeStream(of: Void.self)
    let fixture = try ProjectTests.fixture(
      run: pausingRun(seen, started: starting, release: release))
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    return Harness(fixture: fixture, seen: seen, started: started, release: releasing)
  }

  /// Starts a run, pauses it during its first lane and lets it end.
  static func pausedRun(_ harness: Harness) async throws -> RunViewModel {
    let window = harness.fixture.window
    window.startRun()
    for await _ in harness.started { break }
    let run = try #require(window.run)
    #expect(run.canPause)
    window.pauseRun()
    #expect(run.pauseRequested && !run.canPause, "asked once; the run says it pauses after RGB")
    #expect(run.isRunning, "the lane goes on until its master is written")
    harness.release.yield()
    await run.settled()
    return run
  }

  @Test(
    "Pause keeps a paused stack row; a reopened window lists it; Continue completes it",
    .scratchDirectory)
  func testPauseContinueDiscard() async throws {
    let harness = try Self.harness()
    let fixture = harness.fixture
    defer { try? fixture.project.close() }
    let run = try await Self.pausedRun(harness)
    #expect(run.phase == .paused(Self.checkpoint))

    let store = fixture.project.store
    #expect(try store.stacks().isEmpty, "a paused run is no stack the Studio opens")
    let paused = try #require(try store.pausedStacks().first)
    #expect(paused.bundlePath == "stacks/\(ProjectTests.runID)")
    let recorded = try JSONDecoder().decode(
      PreprocessCheckpoint.self, from: Data(try #require(paused.checkpointJSON).utf8))
    #expect(recorded == Self.checkpoint)
    let output = fixture.project.url.appendingPathComponent(paused.bundlePath)
    #expect(
      FileManager.default.fileExists(atPath: output.appendingPathComponent("master_RGB.fits").path))
    let first = try #require(harness.seen.all.first)
    #expect(!FileManager.default.fileExists(atPath: first.work.path), "Siril's work files removed")
    #expect(fixture.window.pausedRuns.map(\.id) == [paused.id])
    #expect(!fixture.window.isStacking && fixture.window.canRun)

    // The project closed and opened again: the paused run is still offered.
    let reopened = ProjectWindowModel(
      store: { fixture.project.store }, folder: { fixture.project.url },
      services: { _ in ImportServices(planning: { try await ImportPlanningStub.empty($0) }) },
      runs: RunServices(
        run: Self.pausingRun(
          harness.seen, started: AsyncStream.makeStream(of: Void.self).1,
          release: AsyncStream.makeStream(of: Void.self).0),
        now: { ProjectTests.start.addingTimeInterval(60) }, scratch: fixture.work, timeZone: .gmt))
    #expect(reopened.pausedRuns.map(\.id) == [paused.id])

    reopened.continueRun(paused.id)
    await reopened.run?.settled()
    let resumed = try #require(harness.seen.all.last)
    #expect(resumed.resuming && resumed.runID == ProjectTests.runID)
    #expect(resumed.output == output, "the same folder: its masters are reused")
    #expect(resumed.pause != nil, "a continued run can pause again")
    #expect(try store.pausedStacks().isEmpty)
    let stack = try #require(try store.stacks().first)
    #expect(stack.id == paused.id && stack.status == .done && stack.checkpointJSON == nil)
    #expect(try store.images(stackID: stack.id).map(\.role) == ["RGB", "Ha"])
    #expect(reopened.pausedRuns.isEmpty)
  }

  @Test("Discard deletes the paused row and the run's folder", .scratchDirectory)
  func testDiscardPausedRun() async throws {
    let harness = try Self.harness()
    let fixture = harness.fixture
    defer { try? fixture.project.close() }
    _ = try await Self.pausedRun(harness)
    let paused = try #require(fixture.window.pausedRuns.first)
    let output = fixture.project.url.appendingPathComponent(paused.bundlePath)

    await fixture.window.discardPausedRun(paused.id)
    #expect(try fixture.project.store.pausedStacks().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(fixture.window.pausedRuns.isEmpty)
    #expect(try fixture.project.store.stacks().isEmpty)
  }

  @Test(
    "a Pause during a queued run's last lane stops the queue once that run is recorded",
    .scratchDirectory)
  func testPauseOnLastLaneStopsQueue() async throws {
    let seen = Recorded<PreprocessRequest>()
    let (started, starting) = AsyncStream.makeStream(of: Void.self)
    let (release, releasing) = AsyncStream.makeStream(of: Void.self)
    let finish = ProjectTests.fakeRun(seen)
    // A one-lane run: nothing is left to pause in it, it finishes once released.
    let run: RunServices.Run = { request in
      AsyncThrowingStream(PreprocessEvent.self) { continuation in
        let task = Task {
          starting.yield()
          for await _ in release { break }
          do {
            for try await event in finish(request) { continuation.yield(event) }
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
    let (project, window, _) = try await ProjectScopeTests.twoObjects(run: run)
    defer { try? project.close() }
    window.startRun()
    for await _ in started { break }
    window.pauseRun()
    releasing.yield()
    await ProjectScopeTests.queueSettled(window)

    #expect(seen.all.count == 1, "the second object never started")
    #expect(try project.store.stacks().count == 1, "the run that finished is recorded")
    #expect(try project.store.pausedStacks().isEmpty, "nothing was paused: nothing to continue")
    #expect(!window.isStacking && window.canRun)
  }

  @Test(
    "Continue shows the paused run's preset and knobs in the frozen panel (R2)",
    .scratchDirectory)
  func testContinueLoadsTheRecordedKnobs() async throws {
    let harness = try Self.harness()
    let fixture = harness.fixture
    defer { try? fixture.project.close() }
    fixture.window.knobs.mode = .nebula
    _ = try await Self.pausedRun(harness)
    let paused = try #require(fixture.window.pausedRuns.first)
    // The user moves the panel after the pause.
    fixture.window.knobs.mode = .deepsky
    fixture.window.continueRun(paused.id)
    #expect(fixture.window.knobs.mode == .nebula, "the panel shows what the run applies")
    await fixture.window.run?.settled()
    #expect(harness.seen.all.last?.mode == .nebula)
  }

  @Test(
    "the Stacking pane lists a paused run with Continue and Discard, in fr and en",
    .scratchDirectory, arguments: ["en", "fr"])
  func testPausedRunsLayOut(_ language: String) async throws {
    let harness = try Self.harness()
    let fixture = harness.fixture
    defer { try? fixture.project.close() }
    _ = try await Self.pausedRun(harness)
    let window = fixture.window
    window.select(.stacking)
    let host = ImportSheetTests.host(
      ProjectWindowView(model: window).environment(\.locale, Locale(identifier: language))
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640 && host.fittingSize.height >= 400)
    host.sizingOptions = [.minSize]
    host.layoutSubtreeIfNeeded()
    try RunPanelTests.attach(host, "run-paused-\(language).png")
    let paused = try #require(window.pausedRuns.first)
    let words = String(
      localized: PausedRunText.words(paused, locale: Locale(identifier: language)))
    #expect(
      words
        == (language == "en"
          ? "Paused run \(ProjectTests.runID) — stacked: RGB · left: RGB-dualband"
          : "Empilement \(ProjectTests.runID) en pause — empilés : RGB · restants : RGB-dualband"))
  }

  @Test(
    "a Continue that pauses again keeps the same row with its new checkpoint",
    .scratchDirectory)
  func testContinuePausedAgain() async throws {
    let harness = try Self.harness()
    let fixture = harness.fixture
    defer { try? fixture.project.close() }
    _ = try await Self.pausedRun(harness)
    let paused = try #require(fixture.window.pausedRuns.first)
    let (started, starting) = AsyncStream.makeStream(of: Void.self)
    let (release, releasing) = AsyncStream.makeStream(of: Void.self)
    let reopened = ProjectWindowModel(
      store: { fixture.project.store }, folder: { fixture.project.url },
      services: { _ in ImportServices(planning: { try await ImportPlanningStub.empty($0) }) },
      runs: RunServices(
        run: Self.pausingRun(harness.seen, started: starting, release: release, pausesAgain: true),
        now: { ProjectTests.start }, scratch: fixture.work, timeZone: .gmt))
    reopened.continueRun(paused.id)
    for await _ in started { break }
    reopened.pauseRun()
    releasing.yield()
    await reopened.run?.settled()
    let rows = try fixture.project.store.pausedStacks()
    #expect(rows.map(\.id) == [paused.id], "the same row, never a second one")
    #expect(try fixture.project.store.stacks().isEmpty)
    #expect(reopened.pausedRuns.map(\.id) == [paused.id])
  }

  @Test("a finished run offers no Pause and ignores a late one")
  func testPauseOnlyWhileRunning() async {
    let model = RunViewModel(runID: "R", output: RunViewModelTests.output)
    model.start({ RunViewModelTests.stream(RunViewModelTests.recorded) })
    await model.settled()
    model.pause()
    #expect(!model.pauseRequested && !model.canPause, "a finished run has nothing to pause")
  }
}
