import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// Collects lines handed to a callback from any isolation domain.
final class LineSink: Sendable {
  private let storage = Mutex<[SirilLine]>([])
  var lines: [SirilLine] { storage.withLock { $0 } }
  func append(_ line: SirilLine) { storage.withLock { $0.append(line) } }
}

@Suite(
  "SirilSession (pipe mode) and SirilRunner (script mode) against a fake siril-cli",
  .serialized, .timeLimit(.minutes(1)))
struct SirilSessionTests {
  @Test(
    "handshake, ordered results, progress forwarded, errors typed, restart after a crash",
    .scratchDirectory)
  func testExecSequenceAndRestart() async throws {
    let scratch = try ScratchDirectory.url
    let binary = try FakeSiril.install(in: scratch)
    let session = SirilSession(binary: binary, workDirectory: scratch)
    try await session.start()
    let sink = LineSink()

    let first = try await session.exec("load a", onLine: sink.append)
    let second = try await session.exec("load b", onLine: sink.append)
    #expect(first == ["done load a"])
    #expect(second == ["done load b"])
    #expect(sink.lines.contains { $0.percent == 50 }, "progress is forwarded")

    await #expect(
      throws: SirilError.commandFailed(
        command: "fail", hint: "Error in line 1: 'fail' could not run")
    ) {
      try await session.exec("fail now")
    }
    #expect(
      try await session.exec("load c") == ["done load c"], "an error leaves the session usable")
    await #expect(
      throws: SirilError.commandFailed(
        command: "quiet", hint: "Commande inconnue : 'quiet' ou pas encore implémentée"),
      "a localized reply without English keywords still reports its last line"
    ) { try await session.exec("quiet x") }

    await #expect(throws: SirilError.restarted(command: "boom")) { try await session.exec("boom") }
    #expect(await session.launches == 2)
    #expect(try await session.exec("load d") == ["done load d"], "a fresh instance answers")
    await session.stop()
  }

  @Test("a session that cannot find siril-cli fails to start with the path", .scratchDirectory)
  func testSirilSession_start_missingBinary() async throws {
    let scratch = try ScratchDirectory.url
    let missing = scratch.appendingPathComponent("nope/siril-cli").path
    let session = SirilSession(binary: missing, workDirectory: scratch)
    await #expect(throws: SirilError.notInstalled(path: missing)) { try await session.start() }
  }

  @Test("script mode writes _astrostack.ssf, streams lines, returns the log", .scratchDirectory)
  func testSirilRunner_script_success() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.live(binary: try FakeSiril.install(in: scratch))
    let sink = LineSink()
    let script = SirilScripts.alignMasters(seq: "ch")

    let log = try await runner.run(script, scratch, sink.append)
    let written = try String(
      contentsOf: scratch.appendingPathComponent("_astrostack.ssf"), encoding: .utf8)
    #expect(written == script.render())
    #expect(log.contains("log: register ch -2pass\n"))
    #expect(sink.lines.map(\.text).contains("link ch -out=."))
    #expect(sink.lines.last?.percent == 100)
  }

  @Test("script mode: a non-zero exit is a typed error with the log's cause", .scratchDirectory)
  func testSirilRunner_script_failure() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.live(binary: try FakeSiril.install(in: scratch))
    let script = SirilScript([.load("fail_me")])
    // The legacy hint: up to three lines before Siril's locator, then the locator.
    let hint = "setext fits; set32bits; load fail_me; Error in line 4: 'load fail_me'."
    await #expect(throws: SirilError.scriptFailed(exitCode: 1, hint: hint)) {
      _ = try await runner.run(script, scratch, { _ in })
    }
  }

  @Test(
    "siril-cli is found from SIRIL_BIN, else the app bundle; absent is a typed error",
    .scratchDirectory)
  func testSirilTool_locate() throws {
    let scratch = try ScratchDirectory.url
    let fake = try FakeSiril.install(in: scratch)
    #expect(try SirilTool.locate(environment: ["SIRIL_BIN": fake]) == fake)
    let missing = scratch.appendingPathComponent("absent").path
    #expect(throws: SirilError.notInstalled(path: missing)) {
      try SirilTool.locate(environment: ["SIRIL_BIN": missing])
    }
    #expect(SirilTool.defaultPath == "/Applications/Siril.app/Contents/MacOS/siril-cli")
    #expect(SirilMode.default == .script, "pipe mode waits for the 0048 byte-identity golden")
  }
}
