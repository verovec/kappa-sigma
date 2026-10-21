import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// The Données scan when it does not finish (0078): a cancel keeps the previous result, a failure
/// is reported and drops the scan it could not reproduce.
@MainActor
@Suite("Données scan — cancel and failure")
struct DataScanFailureTests {
  @Test("a failed rescan drops the scan it could not reproduce", .scratchDirectory)
  func testFailedRescanDropsScan() async throws {
    struct Unmounted: Error {}
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let fails = Mutex(false)
    let window = ProjectWindowModel(
      store: { project.store },
      planning: { _ in
        { request in
          if fails.withLock({ $0 }) { throw Unmounted() }
          return DataScanTests.gapPlan(request)
        }
      })
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.rescan()
    await window.scanSettled()
    #expect(window.statuses[.calibration] == .attention(1))
    fails.withLock { $0 = true }
    window.rescan()
    await window.scanSettled()
    #expect(window.scan == nil)
    #expect(window.statuses[.calibration] == .ready)
    #expect(window.error != nil)
  }

  @Test("cancelling stops the scan and keeps the previous result", .scratchDirectory)
  func testCancelKeepsPrevious() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store },
      planning: { _ in
        { _ in
          // A scan that only ends when cancelled: the stream never yields.
          let (stream, continuation) = AsyncStream<Void>.makeStream()
          for await _ in stream {}
          continuation.finish()
          throw CancellationError()
        }
      })
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.rescan()
    window.cancelScan()
    await window.scanSettled()
    #expect(window.isScanning == false)
    #expect(window.scan == nil)
    #expect(window.error == nil, "a cancel is not an error")
  }

  @Test("a scan that fails is reported, never silent", .scratchDirectory)
  func testScanFailure() async throws {
    struct Unreadable: Error {}
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store }, planning: { _ in { _ in throw Unreadable() } })
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.rescan()
    await window.scanSettled()
    #expect(window.isScanning == false)
    #expect(window.error != nil)
  }
}
