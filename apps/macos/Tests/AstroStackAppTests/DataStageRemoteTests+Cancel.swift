import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import StackKit
import TestSupport
import Testing

/// Card 0182: the bucket half of a Rescan runs after the local plan (Run never waits on a bucket,
/// card 0100) but under the window's control — Cancel, a new Rescan and a closing window stop it,
/// one scan at a time writes the rows, and the row says it is being read.
@MainActor
@Suite("Données — a bucket rescan is cancellable, one at a time, and shown")
struct DataStageRemoteCancelTests {
  /// Holds every remote read until `open`, so a test acts while a bucket scan is in flight.
  ///
  /// It never throws on cancellation, as a planner past its last check would not: the window's
  /// own guards are what keep a stopped scan from writing.
  @MainActor
  final class Gate {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    /// How many reads reached the gate.
    private(set) var entered = 0

    /// Called by the planner: counts the read, then waits for `open`.
    func pass() async {
      entered += 1
      let waiting = arrivals
      arrivals = []
      for arrival in waiting { arrival.resume() }
      await withCheckedContinuation { held.append($0) }
    }

    /// Returns once `count` reads reached the gate.
    func arrived(_ count: Int) async {
      while entered < count {
        await withCheckedContinuation { arrivals.append($0) }
      }
    }

    /// Lets every held read go on, the latest first when `latestFirst`.
    func open(latestFirst: Bool = false) {
      let waiting = latestFirst ? held.reversed() : held
      held = []
      for read in waiting { read.resume() }
    }
  }

  static let path = "s3://astro/M31/2026-10-18"

  /// Lets a read the window no longer tracks finish, if one still runs: a stopped scan must have
  /// written nothing even once it had every chance to (yields, never a sleep).
  static func drain() async {
    for _ in 0..<20 { await Task.yield() }
  }

  /// A project with one local night and one bucket prefix; its remote reads pass `gate` and the
  /// n-th read answers `lights[n]` lights (the last one past the end).
  static func window(
    _ project: ProjectPackage, gate: Gate, lights: [Int] = [2]
  ) throws -> ProjectWindowModel {
    try project.store.addSource(kind: .night, path: "/c/M31-DB")
    try project.store.addSource(
      remote: DataStageRemoteTests.connection.uuidString, bucket: "astro",
      prefix: "M31/2026-10-18")
    var reads = 0
    let remote: ImportViewModel.RemotePlanning = { @MainActor _, request, _ in
      let count = lights[min(reads, lights.count - 1)]
      reads += 1
      await gate.pass()
      let frames = (0..<count).map { DataStageRemoteTests.FakeRemote.frame($0) }
      return ImportPlan(
        inventory: Inventory(root: request.paths.first ?? "", frames: frames), library: [],
        request: request)
    }
    let window = ProjectWindowModel(
      store: { project.store },
      services: { _ in
        ImportServices(
          planning: { request, _ in
            ImportPlan(
              inventory: Inventory(root: request.paths.first ?? "", frames: []), library: [],
              request: request)
          },
          remotePlanning: remote, browsing: { _, _, _ in [] })
      })
    window.refresh()
    return window
  }

  @Test("testRemoteRescanStopsOnCancel: Cancel stops the bucket half too", .scratchDirectory)
  func testRemoteRescanStopsOnCancel() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let gate = Gate()
    let window = try Self.window(project, gate: gate)

    window.rescan()
    await gate.arrived(1)
    #expect(window.scan != nil, "the local plan is shown before the bucket answers")
    window.cancelScan()
    gate.open()
    await window.scanSettled()
    await Self.drain()

    #expect(window.remoteState(of: Self.path)?.lights == nil, "a cancelled read writes nothing")
    #expect(!window.isScanningRemote && !window.isScanning)
    #expect(window.remoteState(of: Self.path)?.isScanning != true, "the row no longer says so")
  }

  @Test("a second Rescan replaces the first: only its answer lands", .scratchDirectory)
  func testSecondRescanReplacesTheFirst() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let gate = Gate()
    let window = try Self.window(project, gate: gate, lights: [2, 7])

    window.rescan()
    await gate.arrived(1)
    window.rescan()
    await gate.arrived(2)
    // The stale read answers last: were it still a writer, its 2 would overwrite the 7.
    gate.open(latestFirst: true)
    await window.scanSettled()
    await Self.drain()

    #expect(window.remoteState(of: Self.path)?.lights == 7)
    #expect(!window.isScanningRemote)
  }

  @Test(
    "testRemoteRowSaysScanningWhileItRuns: the row and the header say a bucket is being read",
    .scratchDirectory, arguments: ["en", "fr"])
  func testRemoteRowSaysScanningWhileItRuns(language: String) async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let gate = Gate()
    let window = try Self.window(project, gate: gate)
    window.select(.data)

    window.rescan()
    await gate.arrived(1)
    #expect(!window.isScanning, "the local half is over: Run is not held back (card 0100)")
    #expect(window.isScanningRemote)
    #expect(window.remoteState(of: Self.path)?.isScanning == true)
    let reading = AccessibilityAuditTests.entries(
      ProjectWindowView(model: window, projects: .empty), language: language
    ).map(\.id)
    #expect(
      reading.contains(AccessibilityID.dataCancelScan.rawValue), "Cancel while a bucket reads")
    #expect(!reading.contains(AccessibilityID.dataRescan.rawValue))

    gate.open()
    await window.scanSettled()
    #expect(window.remoteState(of: Self.path)?.isScanning == false)
    #expect(window.remoteState(of: Self.path)?.lights == 2, "the count once it answered")
  }

  @Test("scanSettled waits for the bucket half too", .scratchDirectory)
  func testScanSettledWaitsForTheBucket() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let gate = Gate()
    let window = try Self.window(project, gate: gate)

    window.rescan()
    await gate.arrived(1)
    gate.open()
    await window.scanSettled()

    #expect(window.remoteState(of: Self.path)?.lights == 2)
    #expect(!window.isScanningRemote && !window.isScanning)
  }

  @Test("a project of buckets alone offers Rescan in Données", .scratchDirectory)
  func testRemoteOnlyProjectOffersRescan() throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    try project.store.addSource(
      remote: DataStageRemoteTests.connection.uuidString, bucket: "astro",
      prefix: "M31/2026-10-18")
    let window = DataStageRemoteTests.window(project, DataStageRemoteTests.FakeRemote())
    window.refresh()
    window.select(.data)

    let ids = AccessibilityAuditTests.entries(ProjectWindowView(model: window, projects: .empty))
      .map(\.id)
    #expect(ids.contains(AccessibilityID.dataRescan.rawValue), "\(ids)")
  }
}
