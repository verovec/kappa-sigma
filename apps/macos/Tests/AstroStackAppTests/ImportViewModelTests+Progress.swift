import AstroStackApp
import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

extension ImportViewModelTests {
  /// A planner that reports `steps`, then waits for `release` (or its task's cancellation) and
  /// plans like `FakePlanner`, or fails with `failure`.
  final class SteppedPlanner: Sendable {
    let steps: [ScanProgress]
    let failure: Mutex<(any Error & Sendable)?> = Mutex(nil)
    private let gate = AsyncStream<Void>.makeStream()

    init(steps: [ScanProgress]) { self.steps = steps }

    func release() { gate.continuation.finish() }

    var planning: ImportViewModel.ProgressPlanning {
      { request, progress in
        for step in self.steps { progress(step) }
        for await _ in self.gate.stream {}
        try Task.checkCancellation()
        if let failure = self.failure.withLock({ $0 }) { throw failure }
        var inventory = Inventory(root: request.paths.first ?? "", frames: [])
        inventory.sets = FakePlanner.sets
        return ImportPlan(inventory: inventory, library: [], request: request)
      }
    }
  }

  /// Lets the main actor run until `condition` holds (bounded: a stuck model fails the test).
  static func until(_ condition: () -> Bool) async {
    for _ in 0..<100_000 where !condition() { await Task.yield() }
  }

  static let steps: [ScanProgress] = [
    .library, .reading(done: 0, total: 70), .reading(done: 32, total: 70),
  ]

  @Test("progress follows the scan's steps and is nil once it succeeds or fails")
  func testScanProgress() async throws {
    for fails in [false, true] {
      let planner = SteppedPlanner(steps: Self.steps)
      if fails { planner.failure.withLock { $0 = InspectError.noFolders } }
      let model = ImportViewModel(planning: planner.planning)
      model.choose(folder: URL(fileURLWithPath: "/c/M31"))
      await Self.until { model.progress == .reading(done: 32, total: 70) }
      #expect(model.progress == .reading(done: 32, total: 70) && model.isScanning)
      planner.release()
      await model.settled()
      #expect(model.progress == nil && !model.isScanning)
      #expect((model.plan == nil) == fails && (model.error != nil) == fails)
    }
  }

  @Test("a calibration-only replan reports nothing")
  func testReplanReportsNothing() async throws {
    let planner = SteppedPlanner(steps: Self.steps)
    planner.release()
    let model = ImportViewModel(planning: planner.planning)
    model.choose(folder: URL(fileURLWithPath: "/c/M31"))
    await model.settled()
    model.setForceCalibration(true)
    #expect(model.progress == nil)
    await model.settled()
    #expect(model.progress == nil && model.request.forceCalibration)
  }

  @Test("cancelling a scan goes back to the last plan and its request, or to nothing")
  func testCancelScanKeepsLastPlan() async throws {
    let first = SteppedPlanner(steps: [])
    first.release()
    let model = ImportViewModel(planning: first.planning)
    model.choose(folder: URL(fileURLWithPath: "/c/M31"))
    await model.settled()
    let shown = try #require(model.plan)

    model.rescan()
    model.choose(folder: URL(fileURLWithPath: "/c/IC1848"))
    model.cancelScan()
    #expect(!model.isScanning && model.progress == nil)
    #expect(model.plan == shown && model.request == ImportRequest(paths: ["/c/M31"]))

    let pending = SteppedPlanner(steps: Self.steps)
    let fresh = ImportViewModel(planning: pending.planning)
    fresh.choose(folder: URL(fileURLWithPath: "/c/M31"))
    await Self.until { fresh.progress != nil }
    fresh.cancelScan()
    await fresh.settled()
    #expect(fresh.plan == nil && fresh.request.paths.isEmpty && fresh.progress == nil)
  }
}
