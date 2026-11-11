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

  @Test(
    "testLongCommand_RunsAsAScript: a line Siril would not read from its pipe goes to script mode",
    .scratchDirectory, arguments: [(510, true), (511, false), (600, false)])
  func testLongCommand_RunsAsAScript(bytes: Int, throughThePipe: Bool) async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.make(
      mode: .pipe, binary: try FakeSiril.install(in: scratch), work: scratch)
    // `load <name>`: the name pads the line to `bytes`.
    let name = String(repeating: "x", count: bytes - "load ".utf8.count)
    let script = SirilScript([.load(name), .save("b")])

    let log = try await runner.run(script, scratch.appendingPathComponent("lane")) { _ in }

    #expect(log.contains("load " + name) && log.contains("save b"), "the same commands either way")
    #expect(
      log.contains("done cd ") == throughThePipe,
      "\(bytes) bytes: \(throughThePipe ? "command by command" : "the whole script, from a file")"
    )
  }

  @Test(
    "what fits the pipe: a command of 510 bytes or less — bytes, not characters",
    arguments: [(510, true), (511, false), (3, true), (512, false), (0, true)])
  func testFits(bytes: Int, fits: Bool) {
    let command = String(repeating: "é", count: bytes / 2) + (bytes % 2 == 1 ? "x" : "")
    #expect(command.utf8.count == bytes)
    #expect(SirilSession.fits(command) == fits)
  }

  @Test("a script that leaves the pipe says so, naming the command", .scratchDirectory)
  func testFallbackIsSaid() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.make(
      mode: .pipe, binary: try FakeSiril.install(in: scratch), work: scratch)
    let sink = LineSink()
    let name = String(repeating: "x", count: 600)

    _ = try await runner.run(SirilScript([.load(name)]), scratch.appendingPathComponent("lane")) {
      sink.append($0)
    }

    let note = SirilRunner.fallbackNote("load " + name)
    #expect(note.contains("load") && note.contains("605") && note.contains("510"))
    #expect(sink.lines.first?.text == note, "before the script's own lines")
  }

  @Test(
    "a script with an over-long command is refused whole by the session: nothing is sent",
    .scratchDirectory)
  func testExecScript_RefusedWhole() async throws {
    let scratch = try ScratchDirectory.url
    let session = SirilSession(binary: try FakeSiril.install(in: scratch), workDirectory: scratch)
    let sink = LineSink()
    let long = "calibrate " + String(repeating: "x", count: 600)

    await #expect(throws: SirilError.commandTooLong(command: "calibrate", bytes: long.utf8.count)) {
      _ = try await session.execScript(["load a", long, "save b"], onLine: sink.append)
    }
    let launches = await session.launches
    #expect(sink.lines.isEmpty && launches == 0, "`load a` was not run either")
  }

  @Test(
    "testExec_CommandOverTheLimit_Refused: named, and Siril is not even started",
    .scratchDirectory)
  func testExec_CommandOverTheLimit_Refused() async throws {
    let scratch = try ScratchDirectory.url
    let session = SirilSession(binary: try FakeSiril.install(in: scratch), workDirectory: scratch)
    let long = "calibrate_single " + String(repeating: "x", count: 600)

    await #expect(
      throws: SirilError.commandTooLong(command: "calibrate_single", bytes: long.utf8.count)
    ) {
      _ = try await session.exec(long)
    }
    #expect(await session.launches == 0)
    #expect(try await session.exec("load a") == ["done load a"], "the session still works")
  }

  @Test(
    "an error Siril answers before the command starts fails it, though it names no verb",
    .scratchDirectory)
  func testUnnamedError_FailsTheCommand() async throws {
    let scratch = try ScratchDirectory.url
    let session = SirilSession(binary: try FakeSiril.install(in: scratch), workDirectory: scratch)

    await #expect(
      throws: SirilError.commandFailed(
        command: "malformed", hint: "status: error command too long or malformed")
    ) {
      _ = try await session.exec("malformed -bias=a -dark=b")
    }
    #expect(try await session.exec("load a") == ["done load a"], "the session goes on")
    await #expect(throws: SirilError.self, "a named error is still the command's own") {
      _ = try await session.exec("fail")
    }
  }
}
