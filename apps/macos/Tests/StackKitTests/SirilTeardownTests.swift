import Darwin
import Foundation
import StackKit
import TestSupport
import Testing

/// Nothing Siril started outlives it: Siril 1.4 runs Python checks at every launch, and a Python
/// orphaned mid-launch breaks the bundle's launch constraint — macOS kills it with a crash dialog
/// and Siril then deletes its venv (siril#1957).
@Suite("Siril's children never outlive it", .serialized, .timeLimit(.minutes(1)))
struct SirilTeardownTests {
  @Test("pipe mode: stopping the session stops the child Siril started", .scratchDirectory)
  func testSirilSession_stop_stopsChildren() async throws {
    let scratch = try ScratchDirectory.url
    let session = SirilSession(
      binary: try FakeSiril.install(in: scratch, .spawnsHelper), workDirectory: scratch)
    try await session.start()
    let helper = try Self.helperPID(in: scratch)

    await session.stop()

    #expect(await Self.isGone(helper), "the child outlived Siril")
  }

  @Test("script mode: cancelling the runner stops the child Siril started", .scratchDirectory)
  func testSirilRunner_cancel_stopsChildren() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.live(binary: try FakeSiril.install(in: scratch, .spawnsHelper))
    let (lines, sink) = AsyncStream<Void>.makeStream()
    let run = Task {
      try await runner.run(SirilScript([.load("slow")]), scratch) { _ in sink.yield() }
    }
    for await _ in lines { break }
    let helper = try Self.helperPID(in: scratch)

    run.cancel()
    _ = await run.result

    #expect(await Self.isGone(helper), "the child outlived Siril")
  }

  @Test("script mode: a script that ends leaves no child behind", .scratchDirectory)
  func testSirilRunner_exit_stopsChildren() async throws {
    let scratch = try ScratchDirectory.url
    let runner = SirilRunner.live(binary: try FakeSiril.install(in: scratch, .spawnsHelper))

    _ = try await runner.run(SirilScript([.load("a")]), scratch, { _ in })

    #expect(await Self.isGone(try Self.helperPID(in: scratch)), "the child outlived Siril")
  }

  /// The pid the fake wrote to `helper.pid`.
  private static func helperPID(in folder: URL) throws -> pid_t {
    let text = try String(contentsOf: folder.appendingPathComponent("helper.pid"), encoding: .utf8)
    return try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
  }

  /// Whether `pid` exits within 30 s: kqueue wakes on the exit itself, so a loaded machine only
  /// costs the time the teardown really takes. A pid already gone fails to register (ESRCH).
  @concurrent
  private static func isGone(_ pid: pid_t) async -> Bool {
    let queue = kqueue()
    guard queue >= 0 else { return false }
    defer { close(queue) }
    // The C function shares its name with the struct; a typed reference picks the function.
    let wait:
      (
        Int32, UnsafePointer<kevent>?, Int32, UnsafeMutablePointer<kevent>?, Int32,
        UnsafePointer<timespec>?
      ) -> Int32 = kevent
    var change = kevent(
      ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
      fflags: NOTE_EXIT, data: 0, udata: nil)
    guard wait(queue, &change, 1, nil, 0, nil) == 0 else { return errno == ESRCH }
    var event = kevent()
    var timeout = timespec(tv_sec: 30, tv_nsec: 0)
    return wait(queue, nil, 0, &event, 1, &timeout) == 1
  }
}
