import Darwin
import Foundation
import StackKit
import Testing

/// The host's process table, on processes this test spawns itself: nothing else is signalled.
@Suite("ProcessTable — the host's processes, on children of the test only", .serialized)
struct ProcessTableTests {
  /// A child sleeping 30 s, ignoring SIGTERM when `ignoringTerm`, returned once it said it is
  /// ready (its handler set): a read of its first line, never a sleep. Killed at the end.
  static func child(ignoringTerm: Bool) throws -> Process {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    let ignore = ignoringTerm ? "$SIG{TERM} = 'IGNORE'; " : ""
    process.arguments = ["-e", ignore + "$| = 1; print \"ready\\n\"; sleep 30"]
    process.standardOutput = output
    try process.run()
    let ready = output.fileHandleForReading.readData(ofLength: 6)
    try #require(String(bytes: ready, encoding: .utf8) == "ready\n", "the child started")
    return process
  }

  @Test("this process is known by its pid")
  func testCurrent() throws {
    #expect(try #require(ProcessTable.current).pid == getpid())
  }

  @Test("a process reads with the same start time each time")
  func testIdentityStable() throws {
    #expect(ProcessTable.live.identity(getpid()) == ProcessTable.current)
  }

  @Test("no process answers for pid 0")
  func testNoPIDZero() {
    #expect(ProcessTable.live.identity(0) == nil)
  }

  @Test(
    "terminate stops a child: SIGTERM, then SIGKILL when it ignores SIGTERM",
    .timeLimit(.minutes(1)), arguments: [false, true])
  func testTerminate(_ ignoringTerm: Bool) throws {
    let clock = ContinuousClock()
    let start = clock.now
    let process = try Self.child(ignoringTerm: ignoringTerm)
    let pid = process.processIdentifier
    defer { if process.isRunning { kill(pid, SIGKILL) } }
    let started = try #require(ProcessTable.live.identity(pid))

    ProcessTable.live.terminate(started)

    #expect(ProcessTable.live.identity(pid) != started, "gone, or a zombie no longer running")
    // Only an ignored SIGTERM waits out the 2 s grace before SIGKILL: the path really ran.
    #expect((clock.now - start >= .seconds(2)) == ignoringTerm)
  }

  @Test("terminate never signals a pid whose start time differs (a reused pid)")
  func testReusedPIDNotSignalled() throws {
    let process = try Self.child(ignoringTerm: false)
    let pid = process.processIdentifier
    defer { if process.isRunning { kill(pid, SIGKILL) } }
    var recorded = try #require(ProcessTable.live.identity(pid))
    recorded.startSeconds -= 1

    ProcessTable.live.terminate(recorded)

    #expect(process.isRunning, "another process than the one recorded: left alone")
  }
}
