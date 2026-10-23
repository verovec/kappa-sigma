import Foundation
import StackKit
import TestSupport
import Testing

/// Pause and resume at a lane boundary (card 0097): a paused run stops after the lane it is in,
/// keeping that lane's master and record; a resume skips every lane whose master and record match
/// the request and stacks the rest, ending on the bundle an uninterrupted run writes.
@Suite("Preprocessor — pause after a lane, resume skipping the lanes done")
struct PreprocessorPauseTests {
  /// The golden single night reduced to its L and R lanes, into `name`'s own folders.
  static func request(_ name: String, settings: PreprocessSettings = .recorded) throws
    -> PreprocessRequest
  {
    let root = try InventoryBuilderFallbackTests.folder("scan-\(name)")
    var inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
    inventory.sets.removeAll { $0.key.type == .light && !["L", "R"].contains($0.key.filter) }
    return PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/PAUSE"),
      work: root.appendingPathComponent("work/run_PAUSE"), runID: "PAUSE", settings: settings)
  }

  static func resuming(_ request: PreprocessRequest) -> PreprocessRequest {
    var request = request
    request.resuming = true
    return request
  }

  static func siril() -> PipelineSiril {
    PipelineSiril { _ in nil }
  }

  /// Runs `request` over `siril`, asking the run to pause while lane L registers (inside the
  /// lane, synchronously: the stream's consumer may see the lane begin only once it ended).
  @discardableResult
  static func runPausingInL(_ request: PreprocessRequest) async throws -> (
    events: [PreprocessEvent], siril: PipelineSiril
  ) {
    let gate = PauseGate()
    var request = request
    request.pause = gate
    let pausing = PipelineSiril { _ in
      nil
    } onRun: { script in
      if script.contains("\nregister ") { gate.request() }
    }
    var events: [PreprocessEvent] = []
    let tools = PreprocessorTests.tools(pausing)
    for try await event in Preprocessor(tools: tools).run(request) { events.append(event) }
    return (events, pausing)
  }

  /// Every script run in lane `lane`'s light folder.
  static func laneCalls(_ siril: PipelineSiril, _ lane: String) -> [PipelineSiril.Call] {
    siril.calls.filter { $0.directory.lastPathComponent == "light_\(lane)" }
  }

  @Test(
    "a pause during lane L ends the run after L: master and record kept, R never started",
    .scratchDirectory)
  func testPauseAfterLaneKeepsMasters() async throws {
    let request = try Self.request("pause")
    let (events, siril) = try await Self.runPausingInL(request)
    guard case .paused(let checkpoint) = try #require(events.last) else {
      Issue.record("the last event is not .paused: \(String(describing: events.last))")
      return
    }
    #expect(checkpoint.runID == "PAUSE" && checkpoint.lanesDone == ["L"])
    #expect(checkpoint.lanesLeft == ["R"])
    #expect(!events.contains(where: PreprocessorTests.isFinished))
    let output = request.output
    #expect(
      FileManager.default.fileExists(atPath: output.appendingPathComponent("master_L.fits").path))
    #expect(try LaneRecord.read(lane: "L", from: output).outcome.filter == "L")
    #expect(!Self.laneCalls(siril, "L").isEmpty)
    #expect(Self.laneCalls(siril, "R").isEmpty)
    #expect(
      !FileManager.default.fileExists(atPath: output.appendingPathComponent("bundle.json").path))
  }

  @Test(
    "a resume skips lane L (no Siril call), stacks R, writes the uninterrupted bundle",
    .scratchDirectory)
  func testResumeSkipsDoneLanes() async throws {
    // The same folders for both runs: Siril's scripts name them, byte for byte.
    let request = try Self.request("resume")
    let reference = Self.siril()
    let (_, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(reference)).run(request))
    #expect(error == nil)
    let files = [BundleWriter.fileName, GradesRecord.fileName]
    let straight = try files.map { try Data(contentsOf: request.output.appendingPathComponent($0)) }
    for folder in [request.output, request.work] { try FileManager.default.removeItem(at: folder) }

    try await Self.runPausingInL(request)
    let resumed = Self.siril()
    let (events, resumeError) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(resumed)).run(Self.resuming(request)))
    #expect(resumeError == nil)
    guard case .finished(let result) = try #require(events.last) else {
      Issue.record("the resumed run did not finish")
      return
    }
    #expect(result.channels.map(\.filter) == ["L", "R"])
    #expect(Self.laneCalls(resumed, "L").isEmpty)
    #expect(
      Self.laneCalls(resumed, "R").map(\.script) == Self.laneCalls(reference, "R").map(\.script))
    for (file, bytes) in zip(files, straight) {
      let written = try Data(contentsOf: request.output.appendingPathComponent(file))
      #expect(written == bytes, "\(file) differs from the uninterrupted run")
    }
    let journal = events.compactMap { event -> String? in
      if case .progress(let progress) = event { return progress.line }
      return nil
    }
    #expect(journal.contains { $0.hasPrefix("L: reusing master_L") })
  }

  /// What changes between the pause and the resume, and the reason the journal must give.
  struct Change: Sendable, CustomTestStringConvertible {
    var name: String
    var reason: String
    var apply: @Sendable (inout PreprocessRequest) -> Void
    var testDescription: String { name }
  }

  static let changes: [Change] = [
    Change(name: "a setting", reason: "the settings changed") { $0.settings.trailMaskK = 4 },
    Change(name: "the frame set", reason: "the frames changed") { request in
      if let index = request.inventory.sets.firstIndex(where: {
        $0.key.type == .light && $0.key.filter == "L"
      }) {
        request.inventory.sets[index].frames.removeLast()
      }
    },
  ]

  @Test(
    "a changed request re-runs the lane, with the reason in the journal",
    .scratchDirectory, arguments: changes)
  func testResumeRefusesChangedRequest(_ change: Change) async throws {
    var request = try Self.request("changed")
    try await Self.runPausingInL(request)
    change.apply(&request)
    let resumed = Self.siril()
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(resumed)).run(Self.resuming(request)))
    #expect(error == nil)
    #expect(!Self.laneCalls(resumed, "L").isEmpty)
    let lines = events.compactMap { event -> String? in
      if case .progress(let progress) = event { return progress.line }
      return nil
    }
    #expect(lines.contains { $0.contains("L re-runs") && $0.contains(change.reason) }, "\(lines)")
  }

  @Test(
    "a resume with nothing recorded runs every lane, saying nothing to reuse",
    .scratchDirectory)
  func testResumeWithoutRecordsRunsAll() async throws {
    let request = try Self.request("empty")
    let siril = Self.siril()
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(siril)).run(Self.resuming(request)))
    #expect(error == nil)
    #expect(events.last.map(PreprocessorTests.isFinished) == true)
    #expect(!Self.laneCalls(siril, "L").isEmpty && !Self.laneCalls(siril, "R").isEmpty)
  }

  @Test("a calibration frame replaced in place re-runs the lane", .scratchDirectory)
  func testResumeSeesReplacedCalibration() async throws {
    let request = try Self.request("calibration")
    try await Self.runPausingInL(request)
    let dark = try #require(
      request.inventory.sets.first { $0.key.type != .light }?.frames.first?.path)
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: dark))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(repeating: 0, count: 2880))
    try handle.close()
    let resumed = Self.siril()
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(resumed)).run(Self.resuming(request)))
    #expect(error == nil)
    #expect(!Self.laneCalls(resumed, "L").isEmpty)
    #expect(Self.journal(events).contains { $0 == "L re-runs: the frames changed" })
  }

  @Test("an output folder moved between pause and resume keeps its lanes", .scratchDirectory)
  func testResumeAfterMove() async throws {
    var request = try Self.request("moved")
    try await Self.runPausingInL(request)
    let moved = request.output.deletingLastPathComponent().appendingPathComponent("MOVED")
    try FileManager.default.moveItem(at: request.output, to: moved)
    request.output = moved
    let resumed = Self.siril()
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(resumed)).run(Self.resuming(request)))
    #expect(error == nil)
    #expect(Self.laneCalls(resumed, "L").isEmpty)
    guard case .finished(let result) = try #require(events.last) else {
      Issue.record("the resumed run did not finish")
      return
    }
    #expect(result.channels.first?.masterPath == moved.appendingPathComponent("master_L.fits").path)
  }

  @Test(
    "a run without a gate writes no lane record: its folder is the one it always wrote",
    .scratchDirectory)
  func testNoGateNoRecords() async throws {
    let request = try Self.request("plain")
    let (_, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(Self.siril())).run(request))
    #expect(error == nil)
    let lanes = request.output.appendingPathComponent(LaneRecord.folderName)
    #expect(!FileManager.default.fileExists(atPath: lanes.path))
  }

  @Test(
    "an unreadable record re-runs its lane, saying so under that lane's step", .scratchDirectory)
  func testUnreadableRecordSaidUnderItsLane() async throws {
    let request = try Self.request("unreadable")
    try await Self.runPausingInL(request)
    let record = request.output.appendingPathComponent("\(LaneRecord.folderName)/L.json")
    try Data("{".utf8).write(to: record)
    let resumed = Self.siril()
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(resumed)).run(Self.resuming(request)))
    #expect(error == nil)
    #expect(!Self.laneCalls(resumed, "L").isEmpty)
    let notes = events.compactMap { event -> PreprocessEvent.Progress? in
      if case .progress(let progress) = event, progress.line.contains(" re-runs: ") {
        return progress
      }
      return nil
    }
    #expect(notes.map(\.title) == ["grading + stacking TESTFIELD L"], "\(notes)")
    #expect(notes.first?.line.hasPrefix("L re-runs: its record is unreadable (") == true)
  }

  static func journal(_ events: [PreprocessEvent]) -> [String] {
    events.compactMap { event in
      if case .progress(let progress) = event { return progress.line }
      return nil
    }
  }

  @Test("a gate is one-shot and process-safe: requested stays set")
  func testPauseGate() {
    let gate = PauseGate()
    #expect(!gate.isRequested)
    gate.request()
    gate.request()
    #expect(gate.isRequested)
  }
}
