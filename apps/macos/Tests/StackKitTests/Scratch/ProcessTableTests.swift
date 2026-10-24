import Darwin
import Foundation
import StackKit
import Testing

/// The host's process table, on processes this test spawns itself: nothing else is signalled.
@Suite("ProcessTable — the host's processes, on children of the test only", .serialized)
struct ProcessTableTests {
  /// A child running `/bin/sleep 30` (ignoring SIGTERM when `ignoringTerm`); killed at the end.
  static func child(ignoringTerm: Bool) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    let trap = ignoringTerm ? "trap '' TERM; " : ""
    process.arguments = ["-c", trap + "exec /bin/sleep 30"]
    try process.run()
    return process
  }

  /// Waits (bounded) for the shell to have exec'd `/bin/sleep`.
  static func sleeping(_ pid: Int32) -> Bool {
    for _ in 0..<100 {
      if ProcessTable.live.executable(pid) == "/bin/sleep" { return true }
      usleep(10_000)
    }
    return false
  }

  @Test("this process is known; no process answers for pid 0")
  func testIdentity() throws {
    let current = try #require(ProcessTable.current)
    #expect(current.pid == getpid())
    #expect(ProcessTable.live.identity(getpid()) == current, "the same start time each time")
    #expect(ProcessTable.live.identity(0) == nil)
  }

  @Test(
    "terminate stops a child: SIGTERM, then SIGKILL when it ignores SIGTERM",
    .timeLimit(.minutes(1)), arguments: [false, true])
  func testTerminate(_ ignoringTerm: Bool) throws {
    let process = try Self.child(ignoringTerm: ignoringTerm)
    let pid = process.processIdentifier
    defer { if process.isRunning { kill(pid, SIGKILL) } }
    #expect(Self.sleeping(pid))
    let started = try #require(ProcessTable.live.identity(pid))

    ProcessTable.live.terminate(pid)

    #expect(ProcessTable.live.identity(pid) != started, "gone, or a zombie no longer running")
  }
}
