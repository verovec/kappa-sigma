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

  @Test("script mode is one siril-cli -s per script", .scratchDirectory)
  func testScriptMode() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.make(
      mode: .script, binary: try FakeSiril.install(in: scratch), work: scratch)
    let log = try await runner.run(SirilScript([.load("a")]), scratch) { _ in }
    #expect(log.contains("load a"))
  }
}
