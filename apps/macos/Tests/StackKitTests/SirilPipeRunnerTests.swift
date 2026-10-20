import Foundation
import StackKit
import TestSupport
import Testing

/// `SirilRunner.pipe` replays a script through one session: a `cd` to the script's folder, then
/// the header and every command, in order; `make(mode:)` picks the mode.
@Suite(
  "SirilRunner over a pipe session, against a fake siril-cli", .serialized, .timeLimit(.minutes(1)))
struct SirilPipeRunnerTests {
  @Test("cd, header, commands: one exec each, in order, logs joined", .scratchDirectory)
  func testPipeRunner() async throws {
    let scratch = try ScratchDirectory.url
    let binary = try FakeSiril.install(in: scratch)
    let folder = scratch.appendingPathComponent("light_L")
    let runner = SirilRunner.make(mode: .pipe, binary: binary, work: scratch)
    let log = try await runner.run(SirilScript([.load("a"), .save("b")]), folder) { _ in }
    #expect(
      log
        == [
          "done cd \"\(folder.path)\"", "done requires 1.2.0", "done setext fits", "done set32bits",
          "done load a", "done save b",
        ].map { $0 + "\n" }.joined())
    #expect(FileManager.default.fileExists(atPath: folder.path))
  }

  @Test(
    "two scripts on one session never interleave: each runs whole, from its own folder",
    .scratchDirectory)
  func testPipeRunner_scriptsAreUnits() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.make(
      mode: .pipe, binary: try FakeSiril.install(in: scratch), work: scratch)
    let sink = LineSink()
    let script = SirilScript([.load("x"), .save("y"), .load("z")])
    async let first = runner.run(script, scratch.appendingPathComponent("a")) { sink.append($0) }
    async let second = runner.run(script, scratch.appendingPathComponent("b")) { sink.append($0) }
    _ = try await (first, second)
    let done = sink.lines.map(\.text).filter { $0.hasPrefix("done ") }
    #expect(done.count == 14)
    for start in [0, 7] {
      let unit = done[start..<start + 7]
      #expect(unit.first?.hasPrefix("done cd ") == true)
      #expect(unit.dropFirst().allSatisfy { !$0.hasPrefix("done cd ") })
    }
  }

  @Test("script mode is one siril-cli -s per script", .scratchDirectory)
  func testScriptMode() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.make(
      mode: .script, binary: try FakeSiril.install(in: scratch), work: scratch)
    let log = try await runner.run(SirilScript([.load("a")]), scratch) { _ in }
    #expect(log.contains("load a"))
  }
}
