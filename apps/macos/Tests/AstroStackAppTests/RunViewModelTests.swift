import AstroStackApp
import Foundation
import StackKit
import TestSupport
import Testing

/// The Run panel's state: a run's event stream reduces to step states, the preview strip and the
/// journal; Cancel stops the run's task and lists what the run left in its folder.
@MainActor
@Suite("RunViewModel — event reduction, journal, cancel and failure")
struct RunViewModelTests {
  nonisolated static let output = URL(fileURLWithPath: "/p/M31.astrostack/stacks/20261021_210000")

  nonisolated static func begin(_ step: Int, _ title: String) -> PreprocessEvent {
    .progress(.init(step: step, steps: 5, title: title, percent: nil, line: ""))
  }

  nonisolated static func line(_ step: Int, _ title: String, _ text: String, _ percent: Int? = nil)
    -> PreprocessEvent
  {
    .progress(.init(step: step, steps: 5, title: title, percent: percent, line: text))
  }

  /// A stream of `events`, ending with `error` or finished.
  nonisolated static func stream(_ events: [PreprocessEvent], ending error: (any Error)? = nil)
    -> AsyncThrowingStream<PreprocessEvent, any Error>
  {
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: PreprocessEvent.self)
    for event in events { continuation.yield(event) }
    continuation.finish(throwing: error)
    return stream
  }

  nonisolated static let masters = "building master calibration frames"
  nonisolated static let stacking = "grading + stacking M31 RGB"

  /// The stream of a one-lane colour night, as `Preprocessor` emits it (titles from
  /// `Preprocessor+Steps.swift`, lines as `RunEmitter` forwards Siril's).
  nonisolated static let recorded: [PreprocessEvent] = [
    begin(1, masters),
    line(1, masters, "Stacking: 40%", 40),
    begin(2, stacking),
    line(2, stacking, "⚠ 2 frames rejected by grading"),
    .preview(.init(stage: "master_RGB", pngPath: output.path + "/master_RGB_preview.png")),
    begin(3, "aligning channels"),
    begin(4, "combining channels (Siril)"),
    .preview(.init(stage: "combined", pngPath: output.path + "/combined_preview.png")),
    begin(5, "writing the linear bundle"),
    .finished(finished),
  ]

  nonisolated static var finished: PreprocessResult {
    var result = PreprocessResult(runID: "20261021_210000")
    result.notes = ["dual-band split into syn_Ha and syn_OIII"]
    return result
  }

  /// After the first `count` events: the steps (✓ done, ▶ running, · pending), the percentage,
  /// the preview stages and the journal.
  struct Case: Sendable, CustomTestStringConvertible {
    let count: Int
    let steps: String
    let percent: Int?
    let previews: [String]
    let journal: [String]
    var testDescription: String { "after \(count) events" }
  }

  nonisolated static let cases: [Case] = [
    Case(count: 0, steps: "", percent: nil, previews: [], journal: []),
    Case(count: 1, steps: "▶····", percent: nil, previews: [], journal: []),
    Case(count: 2, steps: "▶····", percent: 40, previews: [], journal: ["Stacking: 40%"]),
    Case(count: 3, steps: "✓▶···", percent: nil, previews: [], journal: ["Stacking: 40%"]),
    Case(
      count: 5, steps: "✓▶···", percent: nil, previews: ["master_RGB"],
      journal: ["Stacking: 40%", "⚠ 2 frames rejected by grading"]),
    Case(
      count: 9, steps: "✓✓✓✓▶", percent: nil, previews: ["master_RGB", "combined"],
      journal: ["Stacking: 40%", "⚠ 2 frames rejected by grading"]),
    Case(
      count: 10, steps: "✓✓✓✓✓", percent: nil, previews: ["master_RGB", "combined"],
      journal: ["Stacking: 40%", "⚠ 2 frames rejected by grading"]),
  ]

  static func states(_ model: RunViewModel) -> String {
    String(
      model.steps.map {
        switch $0.state {
        case .pending: "·"
        case .running: "▶"
        case .done: "✓"
        case .failed: "✗"
        case .cancelled: "⊘"
        }
      })
  }

  @Test("a recorded event stream reduces to step states, previews and journal", arguments: cases)
  func testEventReduction(_ row: Case) {
    let model = RunViewModel(runID: "20261021_210000", output: Self.output)
    for event in Self.recorded.prefix(row.count) { model.reduce(event) }

    #expect(Self.states(model) == row.steps)
    #expect(model.percent == row.percent)
    #expect(model.previews.map(\.stage) == row.previews)
    #expect(model.journal.map(\.text) == row.journal)
    #expect(model.phase == (row.count == Self.recorded.count ? .finished : .running))
    #expect(model.result == (row.count == Self.recorded.count ? Self.finished : nil))
  }

  @Test("each step keeps its title; a preview of the same stage replaces the older one")
  func testTitlesAndPreviewReplace() {
    let model = RunViewModel(runID: "R", output: Self.output)
    for event in Self.recorded.prefix(5) { model.reduce(event) }
    model.reduce(.preview(.init(stage: "master_RGB", pngPath: "/again.png")))

    #expect(model.steps.map(\.title) == [Self.masters, Self.stacking, "", "", ""])
    #expect(model.previews.map(\.url.path) == ["/again.png"])
  }

  @Test(
    "the journal filter keeps the matching lines, ignoring case",
    arguments: [
      ("", 2), ("stacking", 1), ("REJECTED", 1), ("⚠", 1), ("nothing", 0),
    ])
  func testJournalFilter(_ filter: String, _ shown: Int) {
    let model = RunViewModel(runID: "R", output: Self.output)
    for event in Self.recorded.prefix(5) { model.reduce(event) }
    model.journalFilter = filter
    #expect(model.shownJournal.count == shown)
  }

  @Test("a full run streamed through start finishes and reports its result")
  func testStartFinishes() async {
    let model = RunViewModel(runID: "R", output: Self.output)
    let outcome = Recorded<PreprocessResult>()
    model.start(
      {
        Self.stream(Self.recorded)
      },
      completion: { result in
        if let value = try? result.get() { outcome.append(value) }
      })
    await model.settled()

    #expect(model.phase == .finished)
    #expect(Self.states(model) == "✓✓✓✓✓")
    #expect(outcome.all == [Self.finished])
  }

  @Test("a stream that ends without its result is a failure, never shown as cancelled")
  func testIncompleteStreamFails() async {
    let model = RunViewModel(runID: "R", output: Self.output)
    model.start({ Self.stream(Array(Self.recorded.prefix(3))) })
    await model.settled()

    #expect(model.phase == .failed(.runIncomplete))
    #expect(Self.states(model) == "✓✗···")
  }

  @Test("Cancel cancels the run's task and lists the artifacts the run kept", .scratchDirectory)
  func testCancelKeepsArtifacts() async throws {
    let output = try ScratchDirectory.url.appendingPathComponent("stacks/R")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for name in ["master_RGB.fits", "master_RGB_preview.png", ".lock"] {
      FileManager.default.createFile(
        atPath: output.appendingPathComponent(name).path, contents: nil)
    }
    let (started, signal) = AsyncStream.makeStream(of: Void.self)
    let (terminated, ended) = AsyncStream.makeStream(of: Bool.self)
    let model = RunViewModel(runID: "R", output: output)
    model.start({
      let (events, continuation) = AsyncThrowingStream.makeStream(of: PreprocessEvent.self)
      // The real stream cancels the Preprocessor's task here (`Preprocessor.run`).
      continuation.onTermination = { reason in
        if case .cancelled = reason { ended.yield(true) } else { ended.yield(false) }
        ended.finish()
      }
      continuation.yield(Self.recorded[0])
      signal.yield()
      return events
    })
    for await _ in started { break }
    model.cancel()
    await model.settled()

    #expect(model.phase == .cancelled)
    var reasons: [Bool] = []
    for await cancelled in terminated { reasons.append(cancelled) }
    #expect(reasons == [true], "the stream was cancelled, which stops the Preprocessor's task")
    #expect(model.kept == ["master_RGB.fits", "master_RGB_preview.png"])
    #expect(!model.steps.contains { $0.state == .running })
  }

  @Test(
    "a failed run marks its step, keeps its artifacts and shows the journal tail",
    .scratchDirectory)
  func testFailureKeepsJournalTail() async throws {
    let output = try ScratchDirectory.url.appendingPathComponent("stacks/R")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    FileManager.default.createFile(
      atPath: output.appendingPathComponent("master_RGB.fits").path, contents: nil)
    let lines = (1...30).map { Self.line(2, Self.stacking, "line \($0)") }
    let model = RunViewModel(runID: "R", output: output)
    model.start({
      Self.stream(
        [Self.begin(1, Self.masters), Self.begin(2, Self.stacking)] + lines,
        ending: PreprocessError.noChannels(["RGB: no frame survived"]))
    })
    await model.settled()

    #expect(model.phase == .failed(.preprocess(.noChannels(["RGB: no frame survived"]))))
    #expect(Self.states(model) == "✓✗···")
    #expect(model.journalTail.map(\.text) == (11...30).map { "line \($0)" })
    #expect(model.kept == ["master_RGB.fits"])
  }
}
