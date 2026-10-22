import Foundation
import StackKit
import TestSupport
import Testing

/// The frame-review breakpoint (card 0069): with the `frame_review` knob on, the run pauses per
/// lane right after grading with every grade, the elected reference and a thumbnail per registered
/// frame, and resumes with the user's decisions; off, nothing changes, byte for byte.
@Suite("Preprocessor — the frame-review breakpoint per lane")
struct PreprocessorFrameReviewTests {
  static let trailed = "R0 3 3 0.30 0 0.01 30 H 1 0 0 0 1 0 0 0 1"

  /// The golden single night reduced to its L and R lanes.
  static func request(frameReview: Bool) throws -> PreprocessRequest {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    var inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
    inventory.sets.removeAll { $0.key.type == .light && !["L", "R"].contains($0.key.filter) }
    var settings = PreprocessSettings.recorded
    settings.frameReview = frameReview
    return PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/REVIEW"),
      work: root.appendingPathComponent("work/run_REVIEW"), runID: "REVIEW", settings: settings)
  }

  /// L elects frame 3 as reference; R's third frame is trailed (auto-rejected).
  static func siril() -> PipelineSiril {
    PipelineSiril { folder in
      switch folder {
      case "light_L":
        (["S 'pp_light_' 1 3 3 0 2 0 1"] + Array(repeating: PipelineSiril.healthyLine, count: 3))
          .joined(separator: "\n")
      case "light_R":
        [PipelineSiril.healthyLine, PipelineSiril.healthyLine, trailed].joined(separator: "\n")
      default: nil
      }
    }
  }

  @Test(
    "a frames event per lane, the user's exclude and force-keep reach the stack with reason user",
    .scratchDirectory)
  func testFramesBreakpointPerLane() async throws {
    let request = try Self.request(frameReview: true)
    let siril = Self.siril()
    var paused: [PreprocessEvent.Frames] = []
    var result: PreprocessResult?
    for try await event in Preprocessor(tools: PreprocessorTests.tools(siril)).run(request) {
      switch event {
      case .frames(let frames):
        paused.append(frames)
        // The thumbnails exist while the run waits.
        for thumbnail in frames.thumbnails.compactMap({ $0 }) {
          #expect(FileManager.default.fileExists(atPath: thumbnail), "\(thumbnail)")
        }
        frames.gate.resume(
          frames.lane == "L" ? FrameDecision(exclude: [2]) : FrameDecision(forceKeep: [3]))
      case .finished(let finished): result = finished
      default: break
      }
    }
    #expect(paused.map(\.lane) == ["L", "R"])
    let left = try #require(paused.first)
    #expect(left.grades.count == 3 && left.grades.allSatisfy { $0.fwhm == 3 && !$0.rejected })
    #expect(left.grades.map(\.index) == [1, 2, 3])
    #expect(left.spans == [0..<3] && left.elected == 3)
    #expect(left.nights.count == 3 && left.thumbnails.compactMap { $0 }.count == 3)
    #expect(left.thumbnails[0]?.hasSuffix("frames/L/00001.png") == true)
    let right = try #require(paused.last)
    #expect(right.elected == nil)
    #expect(right.grades[2].rejected && right.grades[2].rejectReason.hasPrefix("trailed/elongated"))

    let channels = try #require(result?.channels)
    #expect(channels.map(\.filter) == ["L", "R"])
    #expect(channels[0].grades.map(\.rejected) == [false, true, false])
    #expect(channels[0].grades[1].rejectReason == ChannelGrading.userReason)
    #expect(channels[0].stackedFrames == 2)
    #expect(channels[1].grades.map(\.rejected) == [false, false, false])
    #expect(
      channels[1].grades[2].rejectReason.hasPrefix(
        ChannelGrading.keptUserPrefix + "trailed/elongated"))
    #expect(channels[1].stackedFrames == 3)
    let stacks = siril.calls.map(\.script).filter { $0.contains("stack r_pp_light_") }
    #expect(stacks.count == 2)
    #expect(stacks[0].contains("select r_pp_light_ 1 3\nunselect r_pp_light_ 2 2\n"))
    #expect(!stacks[1].contains("unselect"))
  }

  @Test(
    "cancelling a paused run ends it with CancellationError; a late answer is harmless",
    .scratchDirectory)
  func testCancelWhilePaused() async throws {
    let request = try Self.request(frameReview: true)
    let (gates, opened) = AsyncStream.makeStream(of: FrameReviewGate.self)
    let preprocessor = Preprocessor(tools: PreprocessorTests.tools(Self.siril()))
    let run = Task {
      try await preprocessor.perform(request) { event in
        if case .frames(let frames) = event { opened.yield(frames.gate) }
      }
    }
    let gate = try #require(await gates.first { _ in true })
    run.cancel()
    await #expect(throws: CancellationError.self) { try await run.value }
    gate.resume(FrameDecision())
    #expect(gate.lane == "L")
  }

  @Test(
    "a grades.json that cannot be written is a warning, never the end of a stacked run",
    .scratchDirectory)
  func testGradesRecordFailureWarns() async throws {
    let request = try Self.request(frameReview: false)
    // A folder where the file goes: the atomic write fails, the lanes are already stacked.
    try FileManager.default.createDirectory(
      at: request.output.appendingPathComponent(GradesRecord.fileName),
      withIntermediateDirectories: true)
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(Self.siril())).run(request))
    #expect(error == nil)
    guard case .finished(let result) = try #require(events.last) else {
      Issue.record("the last event is not .finished")
      return
    }
    #expect(result.bundle != nil)
    #expect(result.warnings.contains { $0.hasPrefix("grades.json not written") })
  }

  @Test("excluding a frame the grader had restored keeps the grader's wording after « was: »")
  func testUserExcludeKeepsProvenance() {
    // Three trailed frames: the grader rejects all, then restores the two sharpest.
    let sequence = SirilSequence(
      parsing: Array(repeating: PipelineSiril.healthyLine, count: 3).joined(separator: "\n"))
    var outcome = ChannelGrading.grade(sequence, frames: [], settings: .recorded) { _ in
      (true, 0.9)
    }
    #expect(outcome.grades.map(\.rejected) == [false, false, true])
    #expect(outcome.grades[0].rejectReason.hasPrefix(Grader.keptStackMinimumPrefix))
    ChannelGrading.apply(FrameDecision(exclude: [1], forceKeep: [3]), to: &outcome)
    #expect(outcome.grades.map(\.rejected) == [true, false, false])
    #expect(
      outcome.grades[0].rejectReason
        == ChannelGrading.userExcludedPrefix + Grader.keptStackMinimumPrefix
        + "trail detected (score 0.90)")
    #expect(
      outcome.grades[2].rejectReason == ChannelGrading.keptUserPrefix
        + "trail detected (score 0.90)")
    #expect(outcome.rejectedRegistered == [1] && outcome.registeredCount == 3)
  }

  @Test("a gate answers once; a second awaiter is refused and the first keeps its wait")
  func testGateAnswersOnce() async throws {
    let gate = FrameReviewGate(lane: "L")
    let first = Task { try await gate.decision() }
    while !gate.isWaiting { await Task.yield() }
    await #expect(throws: CancellationError.self) { try await gate.decision() }
    #expect(gate.isWaiting, "the first awaiter keeps its wait")
    gate.resume(FrameDecision(exclude: [1]))
    gate.resume(FrameDecision(exclude: [2]))
    #expect(try await first.value == FrameDecision(exclude: [1]))
    // Answered before anyone waits: the answer is kept for the wait.
    let early = FrameReviewGate(lane: "R")
    early.resume(FrameDecision(forceKeep: [3]))
    #expect(try await early.decision() == FrameDecision(forceKeep: [3]))
  }

  @Test(
    "knob off: no frames event, scripts equal the recorded case byte for byte", .scratchDirectory)
  func testFrameReviewOffIsByteIdentical() async throws {
    #expect(!PreprocessSettings.preset(.deepsky).frameReview)
    #expect(!PreprocessSettings.preset(.nebula).frameReview)
    let oracle = try OracleFixtureTests.committedCase("golden-single-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
    let playback = PreprocessOracleTests.Playback(try oracle.grades())
    let siril = PipelineSiril(sequence: { playback.sequences[$0] })
    let tools = Preprocessor.Tools(
      runner: siril.runner, trailProbe: { frame, _ in playback.trail(frame) },
      edgeMeasure: { _ in PreprocessOracleTests.cappedEdge })
    let request = PreprocessRequest(
      inventory: inventory,
      output: root.appendingPathComponent("out/TESTFIELD/\(PreprocessOracleTests.runID)"),
      work: root.appendingPathComponent("work/run_\(PreprocessOracleTests.runID)"),
      runID: PreprocessOracleTests.runID, settings: .recorded)
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: tools).run(request))
    #expect(error == nil)
    #expect(!events.contains { if case .frames = $0 { return true } else { return false } })
    let recorded = try oracle.scripts().filter { $0.number <= 18 }
    let ours = siril.calls.map { PreprocessOracleTests.normalize($0.script, root: root) }
    #expect(ours.count >= recorded.count)
    for (index, script) in recorded.enumerated() where index < ours.count {
      #expect(ours[index] == script.text, "script \(script.name)")
    }
  }
}
