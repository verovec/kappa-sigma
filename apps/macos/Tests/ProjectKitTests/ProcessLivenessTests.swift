import Foundation
import ProjectKit
import Testing

/// Whether a process still runs (card 0147): its pid AND its start time — a reused pid is not the
/// same process, a zombie runs nothing, nothing runs with a pid that is not a pid.
@Suite("ProcessLiveness — a pid with its start time, or nothing")
struct ProcessLivenessTests {
  @Test("this process has a stamp, and it is its own")
  func testCurrent() throws {
    let current = try #require(ProcessLiveness.current)
    #expect(current.pid == getpid())
    #expect(ProcessLiveness.stamp(of: getpid()) == current)
    #expect(ProcessLiveness.isRunning(current))
  }

  @Test(
    "no stamp for a pid that is not one, or for a process that is gone",
    arguments: [Int32(0), -1, 999_999])
  func testAbsent(pid: Int32) {
    #expect(ProcessLiveness.stamp(of: pid) == nil)
    #expect(
      !ProcessLiveness.isRunning(ProcessStamp(pid: pid, startSeconds: 1, startMicroseconds: 0)))
  }

  @Test("a stamp with another start time is another process: the parent's pid, a wrong start")
  func testReusedPid() throws {
    // The parent (the test runner) is another live process whose info this user may read.
    let parent = try #require(ProcessLiveness.stamp(of: getppid()))
    #expect(ProcessLiveness.isRunning(parent) && parent.pid != getpid())
    let impostor = ProcessStamp(
      pid: parent.pid, startSeconds: parent.startSeconds + 1, startMicroseconds: 0)
    #expect(!ProcessLiveness.isRunning(impostor))
  }
}
