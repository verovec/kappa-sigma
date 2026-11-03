import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import Testing

/// Card 0169: the Import sheet can read a bucket instead of a folder — the prefix chosen is
/// scanned where it stands, and the disk scanner is never called for it.
@MainActor
@Suite("ImportViewModel — a bucket prefix imported like a folder")
struct ImportViewModelBucketTests {
  static let connection = S3Connection(
    name: "Captures", endpoint: "https://s3.example.com", region: "us-east-1", pathStyle: false,
    accessKey: "AK")

  /// Records every remote target it was asked to scan and answers a plan of one light set.
  @MainActor
  final class FakeRemotePlanner {
    var targets: [RemoteImportTarget] = []
    var requests: [ImportRequest] = []
    var failure: (any Error)?

    var planning: ImportViewModel.RemotePlanning {
      { @MainActor target, request, _ in
        self.targets.append(target)
        self.requests.append(request)
        if let failure = self.failure { throw failure }
        var inventory = Inventory(root: request.paths.first ?? "", frames: [])
        inventory.sets = ImportViewModelTests.FakePlanner.sets
        inventory.notCheckedRemotely = ["s3://astro/M31/2026-10-18/l_1.fits"]
        return ImportPlan(inventory: inventory, library: [], request: request)
      }
    }
  }

  static func bucketModel(prefix: String = "M31/2026-10-18/") -> ImportBucketModel {
    let bucket = ImportBucketModel(connections: [connection], browsing: { _, _, _ in [] })
    bucket.connectionID = connection.id
    bucket.bucket = "astro"
    bucket.enter(prefix)
    return bucket
  }

  @Test("testS3Choice_ScansThePrefix: the chosen prefix is scanned, the disk scanner untouched")
  func testS3Choice_ScansThePrefix() async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let remote = FakeRemotePlanner()
    let bucket = Self.bucketModel()
    let model = ImportViewModel(
      planning: disk.planning, remotePlanning: remote.planning, bucket: bucket)

    model.setSource(.bucket)
    model.choose(bucket: try #require(bucket.target))
    await model.settled()

    #expect(model.source == .bucket)
    #expect(model.request.paths == ["s3://astro/M31/2026-10-18"], "the project's own spelling")
    #expect(remote.targets.map(\.path) == ["s3://astro/M31/2026-10-18"])
    #expect(remote.requests.map(\.paths) == [["s3://astro/M31/2026-10-18"]])
    #expect(disk.requests.isEmpty, "a bucket is never handed to the disk scanner")
    #expect(model.plan?.nights.flatMap(\.sets).count == 3)
    #expect(model.plan?.inventory.notCheckedRemotely.count == 1, "0167's verdict reaches the sheet")
    #expect(model.error == nil && !model.isScanning)
  }

  @Test("an override rescans the bucket, not the disk")
  func testOverrideRescansTheBucket() async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let remote = FakeRemotePlanner()
    let model = ImportViewModel(
      planning: disk.planning, remotePlanning: remote.planning, bucket: Self.bucketModel())
    model.setSource(.bucket)
    model.choose(bucket: try #require(model.bucket?.target))
    await model.settled()

    model.setColorModel(.mono)
    await model.settled()

    #expect(remote.requests.count == 2 && remote.requests.last?.colorModel == .mono)
    #expect(disk.requests.isEmpty)
  }

  @Test("choosing folders again leaves the bucket: the next scan reads the disk")
  func testChoosingFoldersLeavesTheBucket() async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let remote = FakeRemotePlanner()
    let model = ImportViewModel(
      planning: disk.planning, remotePlanning: remote.planning, bucket: Self.bucketModel())
    model.setSource(.bucket)
    model.choose(bucket: try #require(model.bucket?.target))
    await model.settled()

    model.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await model.settled()

    #expect(model.source == .folder, "the sheet follows what was chosen")
    #expect(model.remoteTarget == nil)
    #expect(disk.requests.map(\.paths) == [["/c/M31-DB"]])
    #expect(remote.requests.count == 1, "the bucket is not scanned again")
  }

  @Test("a bucket that fails to scan shows the failure, like a folder that cannot be read")
  func testFailedBucketScanShows() async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let remote = FakeRemotePlanner()
    remote.failure = S3Error.service(
      status: 403, code: "AccessDenied", message: "Access Denied", requestID: nil)
    let model = ImportViewModel(
      planning: disk.planning, remotePlanning: remote.planning, bucket: Self.bucketModel())

    model.setSource(.bucket)
    model.choose(bucket: try #require(model.bucket?.target))
    await model.settled()

    #expect(model.plan == nil && model.error != nil, "never an empty inventory (R2)")
    let shown = String(localized: try #require(model.error).message)
    #expect(shown.contains("Access Denied"), "the service's own words, as sent: \(shown)")
  }

  @Test("without a remote planner the bucket choice scans nothing at all")
  func testNoRemotePlannerScansNothing() async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let model = ImportViewModel(planning: disk.planning)

    model.setSource(.bucket)
    model.choose(
      bucket: RemoteImportTarget(
        connectionID: Self.connection.id, bucket: "astro", prefix: "M31/"))
    await model.settled()

    #expect(disk.requests.isEmpty, "a virtual path is never read as a folder")
    #expect(model.plan == nil)
  }

  @Test("cancelling a scan puts back the side the shown plan was read on, not just its request")
  func testCancelRestoresTheRouting() async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let remote = FakeRemotePlanner()
    let model = ImportViewModel(
      planning: disk.planning, remotePlanning: remote.planning, bucket: Self.bucketModel())
    model.setSource(.bucket)
    model.choose(bucket: try #require(model.bucket?.target))
    await model.settled()

    // A local night chosen next, then its scan cancelled: the bucket's plan comes back, so the
    // bucket must come back with it — Add would otherwise record « s3://… » as a night.
    model.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    model.cancelScan()

    #expect(model.request.paths == ["s3://astro/M31/2026-10-18"])
    #expect(model.source == .bucket)
    #expect(model.remoteTarget?.path == "s3://astro/M31/2026-10-18")
  }

  @Test("the same prefix read through another connection is read again, never replanned")
  func testAnotherConnectionReadsAgain() async throws {
    let disk = ImportViewModelTests.FakePlanner()
    let remote = FakeRemotePlanner()
    let bucket = Self.bucketModel()
    let model = ImportViewModel(
      planning: disk.planning, remotePlanning: remote.planning, bucket: bucket)
    model.choose(bucket: try #require(bucket.target))
    await model.settled()
    let other = RemoteImportTarget(
      connectionID: UUID(), bucket: "astro", prefix: "M31/2026-10-18/")

    model.choose(bucket: other)
    await model.settled()

    #expect(remote.targets.count == 2, "the second connection read the prefix itself")
    #expect(remote.targets.last?.connectionID == other.connectionID)
    #expect(model.remoteTarget == other)
  }
}
