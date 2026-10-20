import Foundation
import StackKit
import TestSupport
import Testing

@Suite(
  "SirilSession under concurrency, cancellation and broken installs", .serialized,
  .timeLimit(.minutes(1)))
struct SirilSessionRobustnessTests {
  @Test("concurrent commands run one at a time, each getting its own reply", .scratchDirectory)
  func testSirilSession_exec_concurrentCallersAreSerialised() async throws {
    let scratch = try ScratchDirectory.url
    let session = SirilSession(binary: try FakeSiril.install(in: scratch), workDirectory: scratch)
    try await session.start()
    let replies = try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
      for index in 0..<8 {
        group.addTask { (index, try await session.exec("load f\(index)")) }
      }
      return try await group.reduce(into: [Int: [String]]()) { $0[$1.0] = $1.1 }
    }
    for index in 0..<8 {
      #expect(replies[index] == ["done load f\(index)"])
    }
    await session.stop()
  }

  @Test(
    "cancelling a command stops Siril and reports cancellation, not a crash",
    .scratchDirectory)
  func testSirilSession_exec_cancellation() async throws {
    let scratch = try ScratchDirectory.url
    let session = SirilSession(binary: try FakeSiril.install(in: scratch), workDirectory: scratch)
    try await session.start()
    // Cancel once Siril has really started the command (no sleeps in tests).
    let (started, signal) = AsyncStream<Void>.makeStream()
    let slow = Task {
      try await session.exec("slow step") { line in
        if line.status == .starting { signal.yield() }
      }
    }
    var iterator = started.makeAsyncIterator()
    _ = await iterator.next()
    slow.cancel()
    await #expect(throws: CancellationError.self) { try await slow.value }
    #expect(
      try await session.exec("load after") == ["done load after"], "the next command starts fresh")
    #expect(await session.launches == 2)
    await session.stop()
  }

  @Test("a Siril that never says ready fails to start within the timeout", .scratchDirectory)
  func testSirilSession_start_readyTimeout() async throws {
    let scratch = try ScratchDirectory.url
    let session = SirilSession(
      binary: try FakeSiril.install(in: scratch, .silent), workDirectory: scratch,
      readyTimeout: .milliseconds(500))
    await #expect(throws: SirilError.sessionFailed(reason: "no `ready` within 0.5 seconds")) {
      try await session.start()
    }
  }

  @Test("a Siril older than 1.4 is refused in both modes", .scratchDirectory)
  func testSirilVersionFloor_enforced() async throws {
    let scratch = try ScratchDirectory.url
    let binary = try FakeSiril.install(in: scratch, .old)
    await #expect(throws: SirilError.tooOld(version: "1.2")) {
      try await SirilSession(binary: binary, workDirectory: scratch).start()
    }
    await #expect(throws: SirilError.tooOld(version: "1.2")) {
      _ = try await SirilRunner.live(binary: binary).run(SirilScript([.mirrorx]), scratch, { _ in })
    }
  }

  @Test("script mode splits on newline only: a bare CR stays inside its line", .scratchDirectory)
  func testSirilRunner_linesSplitOnNewlineOnly() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.live(binary: try FakeSiril.install(in: scratch))
    let log = try await runner.run(SirilScript([.load("a\rb")]), scratch, { _ in })
    #expect(log.contains("log: load a\rb\n"))
  }
}
