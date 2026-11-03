import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import TestSupport
import Testing

/// Card 0169: the Données stage scans a remote source through the connection it was imported
/// with, and a scan that fails says so on that source's row while the last inventory stays —
/// never an empty one, which would read as « the bucket holds nothing » (R2).
@MainActor
@Suite("Données — a remote source's scan, and the failure shown on its row")
struct DataStageRemoteTests {
  static let connection = UUID()

  /// A remote planner that answers `lights` frames until `failure` is set.
  @MainActor
  final class FakeRemote {
    var failure: (any Error)?
    var targets: [RemoteImportTarget] = []
    var lights = 2

    nonisolated static func frame(_ index: Int) -> CaptureFrame {
      var frame = CaptureFrame(path: "s3://astro/M31/2026-10-18/l_\(index).fits")
      frame.type = .light
      frame.session = "2026-10-18"
      return frame
    }

    var planning: ImportViewModel.RemotePlanning {
      { @MainActor target, request, _ in
        self.targets.append(target)
        if let failure = self.failure { throw failure }
        let frames = (0..<self.lights).map { Self.frame($0) }
        var inventory = Inventory(root: request.paths.first ?? "", frames: frames)
        inventory.sets = [
          FrameSet(
            key: SetKey(
              type: .light, object: "M 31", filter: "RGB", exposureMs: 300_000,
              color: true),
            frames: frames, indices: Array(frames.indices))
        ]
        return ImportPlan(inventory: inventory, library: [], request: request)
      }
    }
  }

  static func window(_ project: ProjectPackage, _ remote: FakeRemote) -> ProjectWindowModel {
    ProjectWindowModel(
      store: { project.store },
      services: { _ in
        ImportServices(
          planning: ImportViewModel.reporting(ImportPlanningStub.empty),
          remotePlanning: remote.planning, browsing: { _, _, _ in [] })
      })
  }

  @Test(
    "testRemoteSourceErrorShown: the failure is on the row, the last count stays",
    .scratchDirectory)
  func testRemoteSourceErrorShown() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    try project.store.addSource(
      remote: Self.connection.uuidString, bucket: "astro", prefix: "M31/2026-10-18")
    let remote = FakeRemote()
    let window = Self.window(project, remote)
    window.refresh()

    window.rescan()
    await window.scanSettled()
    let scanned = try #require(window.remoteState(of: "s3://astro/M31/2026-10-18"))
    #expect(scanned.lights == 2 && scanned.failure == nil)
    #expect(remote.targets.map(\.bucket) == ["astro"], "the row's own bucket and prefix")
    #expect(remote.targets.map(\.prefix) == ["M31/2026-10-18"])
    #expect(remote.targets.map(\.connectionID) == [Self.connection], "its stored connection")

    remote.failure = S3Error.service(
      status: 403, code: "AccessDenied", message: "Access Denied", requestID: nil)
    window.rescan()
    await window.scanSettled()

    let failed = try #require(window.remoteState(of: "s3://astro/M31/2026-10-18"))
    let shown = String(localized: try #require(failed.failure).message)
    #expect(shown.contains("Access Denied"), "the service's own words: \(shown)")
    #expect(failed.lights == 2, "the last inventory stays: an empty one would be a verdict")
  }

  @Test("a source whose connection is gone says so instead of scanning", .scratchDirectory)
  func testRemoteSourceWithoutConnection() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    try project.store.addSource(
      remote: Self.connection.uuidString, bucket: "astro", prefix: "M31/2026-10-18")
    let remote = FakeRemote()
    remote.failure = RemoteImportProblem.connectionMissing
    let window = Self.window(project, remote)
    window.refresh()

    window.rescan()
    await window.scanSettled()

    let state = try #require(window.remoteState(of: "s3://astro/M31/2026-10-18"))
    #expect(state.lights == nil && state.failure != nil)
    #expect(
      String(localized: try #require(state.failure).message).contains("Settings"),
      "it names where to fix it")
  }

  @Test("a project of folders alone scans no bucket at all", .scratchDirectory)
  func testLocalOnlyProjectScansNoBucket() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    try project.store.addSource(kind: .night, path: "/c/M31-DB")
    let remote = FakeRemote()
    let window = Self.window(project, remote)
    window.refresh()

    window.rescan()
    await window.scanSettled()

    #expect(remote.targets.isEmpty)
    #expect(window.remoteStates.isEmpty)
  }

  @Test(
    "the pane lays out a remote row: its count, then its failure, in each language",
    .scratchDirectory,
    arguments: [Locale(identifier: "en"), Locale(identifier: "fr")])
  func testRemoteRowLaysOut(locale: Locale) async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    try project.store.addSource(
      remote: Self.connection.uuidString, bucket: "astro", prefix: "M31/2026-10-18")
    let remote = FakeRemote()
    let window = Self.window(project, remote)
    window.refresh()
    let host = ImportSheetTests.host(
      ProjectWindowView(model: window, projects: .empty).environment(\.locale, locale))
    let bare = host.fittingSize

    window.rescan()
    await window.scanSettled()
    host.layoutSubtreeIfNeeded()
    #expect(bare.height > 0 && host.fittingSize.height > 0, "the scanned row lays out")

    remote.failure = S3Error.service(
      status: 403, code: "AccessDenied", message: "Access Denied", requestID: nil)
    window.rescan()
    await window.scanSettled()
    host.layoutSubtreeIfNeeded()

    #expect(window.remoteState(of: "s3://astro/M31/2026-10-18")?.failure != nil)
    #expect(host.fittingSize.height > 0, "the row with its S3 badge lays out too")
  }

  @Test("the row says « S3 403 … » once, not « S3: S3 403 … »", .scratchDirectory)
  func testFailureIsNotPrefixedTwice() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    try project.store.addSource(
      remote: Self.connection.uuidString, bucket: "astro", prefix: "M31/2026-10-18")
    let remote = FakeRemote()
    remote.failure = S3Error.service(
      status: 403, code: "AccessDenied", message: "Access Denied", requestID: nil)
    let window = Self.window(project, remote)
    window.refresh()

    window.rescan()
    await window.scanSettled()

    let state = try #require(window.remoteState(of: "s3://astro/M31/2026-10-18"))
    let shown = String(localized: try #require(state.failure).message)
    #expect(shown.contains("Access Denied"))
    #expect(!shown.contains("S3: S3"), "the error already names S3: \(shown)")
  }

  @Test("an unreachable bucket does not hold back the local scan", .scratchDirectory)
  func testLocalScanIsNotHeldBackByABucket() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    try project.store.addSource(kind: .night, path: "/c/M31-DB")
    try project.store.addSource(
      remote: Self.connection.uuidString, bucket: "astro", prefix: "M31/2026-10-18")
    let remote = FakeRemote()
    remote.failure = RemoteImportProblem.connectionMissing
    let window = ProjectWindowModel(
      store: { project.store },
      services: { _ in
        ImportServices(
          planning: { request, _ in
            ImportPlan(
              inventory: Inventory(root: request.paths.first ?? "", frames: []), library: [],
              request: request)
          },
          remotePlanning: remote.planning, browsing: { _, _, _ in [] })
      })
    window.refresh()

    window.rescan()
    await window.scanSettled()

    #expect(window.scan != nil, "the local plan is shown even though the bucket failed")
    #expect(window.remoteState(of: "s3://astro/M31/2026-10-18")?.failure != nil)
  }

  @Test("a project with no source at all scans nothing, local or remote", .scratchDirectory)
  func testEmptyProjectScansNothing() async throws {
    let project = try ProjectWindowModelTests.package()
    defer { try? project.close() }
    let remote = FakeRemote()
    let window = Self.window(project, remote)
    window.refresh()

    window.rescan()
    await window.scanSettled()

    #expect(remote.targets.isEmpty && window.remoteStates.isEmpty && !window.isScanning)
  }
}
