import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// GraXpert is played by a shell script inside a fake `.app`; the runner's command line, its
/// progress lines, the missing app and every failure are pinned here.
@Suite("GraXpertRunner: CLI, progress, missing app, failures, timeout", .serialized)
struct GraXpertRunnerTests {
  static func input() throws -> URL {
    let url = try ScratchDirectory.url.appendingPathComponent("in.fits")
    try Data("pixels".utf8).write(to: url)
    return url
  }

  @Test(
    "the command line is GraXpert 3's: file first, then -cli -cmd -output -correction -smoothing",
    arguments: [
      (BackgroundCorrection.subtract, 0.5, "Subtraction", "0.5"),
      (.divide, 1, "Division", "1"), (.subtract, 0.25, "Subtraction", "0.25"),
    ])
  func testArguments(
    correction: BackgroundCorrection, smoothing: Double, word: String, number: String
  ) {
    let input = URL(fileURLWithPath: "/in/base.fits")
    let output = URL(fileURLWithPath: "/out/corrected.fits")
    let arguments = GraXpertRunner.arguments(
      input: input, output: output,
      options: GraXpertRunner.Options(smoothing: smoothing, correction: correction))
    #expect(
      arguments == [
        "/in/base.fits", "-cli", "-cmd", "background-extraction", "-output",
        "/out/corrected", "-correction", word, "-smoothing", number,
      ])
  }

  @Test("an output of another extension than the input is passed whole")
  func testOutputOfAnotherExtension() {
    let arguments = GraXpertRunner.arguments(
      input: URL(fileURLWithPath: "/in/base.fit"), output: URL(fileURLWithPath: "/out/c.fits"),
      options: GraXpertRunner.Options(smoothing: 0.5, correction: .subtract))
    #expect(arguments[5] == "/out/c.fits")
  }

  @Test("the executable is Contents/MacOS/GraXpert inside the located app")
  func testBinaryInsideApp() {
    #expect(
      GraXpertRunner.binary(inApp: "/Applications/GraXpert.app")
        == "/Applications/GraXpert.app/Contents/MacOS/GraXpert")
  }

  @Test("progress lines are forwarded in order with their percentage", .scratchDirectory)
  func testProgressAndOutput() async throws {
    let app = try FakeGraXpert.install(in: try ScratchDirectory.url)
    let output = try ScratchDirectory.url.appendingPathComponent("out.fits")
    let seen = Mutex<[ToolProgress]>([])
    let tools = HostTools { _ in .found(path: app, version: nil) }
    let log = try await GraXpertRunner.located(by: tools).run(
      try Self.input(), output, GraXpertRunner.Options(smoothing: 0.5, correction: .subtract)
    ) { progress in seen.withLock { $0.append(progress) } }
    #expect(
      seen.withLock { $0 } == [
        ToolProgress(line: "INFO Background extraction 50%", percent: 50),
        ToolProgress(line: "INFO Saving 100%", percent: 100),
      ])
    #expect(log == "INFO Background extraction 50%\nINFO Saving 100%\n")
    #expect(try Data(contentsOf: output) == Data("pixels".utf8))
  }

  @Test("a missing GraXpert is GraXpertError.missing with the path HostTools looked at")
  func testMissingApp() async throws {
    let tools = HostTools { _ in .missing(path: "/Applications/GraXpert.app") }
    await #expect(throws: GraXpertError.missing(path: "/Applications/GraXpert.app")) {
      try await GraXpertRunner.located(by: tools)
    }
  }

  @Test(
    "a failing GraXpert throws its exit code and log; a silent one, the missing output",
    .scratchDirectory)
  func testFailures() async throws {
    let output = try ScratchDirectory.url.appendingPathComponent("out.fits")
    let options = GraXpertRunner.Options(smoothing: 0.5, correction: .subtract)
    let failing = try FakeGraXpert.install(
      in: try ScratchDirectory.url, script: "#!/bin/sh\necho 'no AI model'\nexit 3\n",
      named: "Failing.app")
    await #expect(throws: GraXpertError.failed(exitCode: 3, log: "no AI model\n")) {
      try await GraXpertRunner.live(app: failing).run(try Self.input(), output, options) { _ in }
    }
    let silent = try FakeGraXpert.install(
      in: try ScratchDirectory.url, script: "#!/bin/sh\nexit 0\n", named: "Silent.app")
    await #expect(throws: GraXpertError.noOutput(path: output.path)) {
      try await GraXpertRunner.live(app: silent).run(try Self.input(), output, options) { _ in }
    }
  }

  @Test(
    "a `Critical error` line is a failure even on exit 0 (the legacy firstErrorLine)",
    .scratchDirectory)
  func testCriticalErrorOnCleanExit() async throws {
    let output = try ScratchDirectory.url.appendingPathComponent("out.fits")
    let script = FakeGraXpert.script.replacingOccurrences(
      of: "echo \"INFO Saving 100%\"", with: "echo \"  Critical error: onnxruntime failed  \"")
    let broken = try FakeGraXpert.install(
      in: try ScratchDirectory.url, script: script, named: "Broken.app")
    await #expect(throws: GraXpertError.reportedError(line: "Critical error: onnxruntime failed")) {
      try await GraXpertRunner.live(app: broken).run(
        try Self.input(), output, GraXpertRunner.Options(smoothing: 0.5, correction: .subtract)
      ) { _ in }
    }
    #expect(GraXpertRunner.criticalError(in: "INFO ok\nINFO done\n") == nil)
  }

  @Test("a GraXpert that outlives the timeout is stopped and reported", .scratchDirectory)
  func testTimeout() async throws {
    let output = try ScratchDirectory.url.appendingPathComponent("out.fits")
    let stuck = try FakeGraXpert.install(
      in: try ScratchDirectory.url, script: "#!/bin/sh\nsleep 30\n", named: "Stuck.app")
    let runner = GraXpertRunner.live(app: stuck, timeout: .milliseconds(300))
    let started = ContinuousClock.now
    await #expect(throws: GraXpertError.timedOut(after: .milliseconds(300))) {
      try await runner.run(
        try Self.input(), output, GraXpertRunner.Options(smoothing: 0.5, correction: .subtract)
      ) { _ in }
    }
    // Stopped by the teardown, not by the script's own end.
    #expect(ContinuousClock.now - started < .seconds(10))
  }
}
