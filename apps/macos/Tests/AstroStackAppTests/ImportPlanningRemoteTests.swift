import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0169: the app's half of a bucket import — the client of a Settings connection, « Browse »
/// over one level, and the scan that keeps what it read with the project (card 0168).
@Suite("ImportPlanning — browsing and scanning a bucket")
struct ImportPlanningRemoteTests {
  static let connection = UUID()

  /// A ListObjectsV2 answer with `folders` as its sub-prefixes and no object.
  static func level(_ folders: [String]) -> Data {
    let common = folders.map { "<CommonPrefixes><Prefix>\($0)</Prefix></CommonPrefixes>" }.joined()
    return Data(
      ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        + "<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
        + "<Name>astro</Name><KeyCount>0</KeyCount><IsTruncated>false</IsTruncated>"
        + "<EncodingType>url</EncodingType>" + common + "</ListBucketResult>").utf8)
  }

  /// A client answering `body` to every request, recording the query it was sent.
  static func client(_ body: @escaping @Sendable (HTTPRequest) -> Data) throws -> S3Client {
    let endpoint = try S3Endpoint(
      url: try #require(URL(string: "http://127.0.0.1:9000")), region: "us-east-1",
      addressing: .pathStyle)
    return S3Client(
      endpoint: endpoint,
      credentials: S3Credentials(accessKey: "AK", secretKey: "secret"),
      transport: HTTPTransport(
        send: { request in
          HTTPResponse(status: 200, headers: [:], body: body(request))
        },
        download: { _, _, _ in HTTPResponse(status: 200, headers: [:], body: Data()) }))
  }

  @Test("Browse lists one level, asking for the delimiter that cuts it")
  func testBrowsingListsOneLevel() async throws {
    let asked = Mutex<[String]>([])
    let client = try Self.client { request in
      asked.withLock { $0.append(request.url.query() ?? "") }
      return Self.level(["M31/2026-10-18/", "M31/2026-10-19/"])
    }

    let folders = try await ImportPlanning.browsing(client: { _ in client })(
      Self.connection, "astro", "M31/")

    #expect(folders == ["M31/2026-10-18/", "M31/2026-10-19/"])
    let query = try #require(asked.withLock { $0.first })
    #expect(query.contains("delimiter=%2F") || query.contains("delimiter=/"), "one level: \(query)")
    #expect(query.contains("prefix=M31%2F") || query.contains("prefix=M31/"))
  }

  @Test("a connection gone from Settings is said, never answered with an empty bucket")
  func testBrowsingWithoutConnection() async throws {
    await #expect(throws: RemoteImportProblem.connectionMissing) {
      _ = try await ImportPlanning.browsing(client: { _ in nil })(Self.connection, "astro", "")
    }
  }

  @Test("a scan of a bucket keeps what it read with the project", .scratchDirectory)
  func testRemotePlanningKeepsItsScan() async throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("R.astrostack"))
    defer { try? project.close() }
    let store = project.store
    let client = try Self.client { _ in Self.level([]) }
    let planning = ImportPlanning.remotePlanning(
      store: store, index: LibraryIndex(store: store, folder: try ScratchDirectory.url),
      client: { _ in client })
    let target = RemoteImportTarget(
      connectionID: Self.connection, bucket: "astro", prefix: "M31/2026-10-18")

    let plan = try await planning(target, ImportRequest(paths: [target.path])) { _ in }

    #expect(plan.inventory.frames.isEmpty, "an empty prefix is an empty inventory, said as such")
    #expect(plan.inventory.root == "s3://astro/M31/2026-10-18")
    let kept = try #require(try store.remoteScan(of: target.path))
    #expect(try RemoteScanCache(json: kept).entries.isEmpty, "nothing was read, nothing cached")
  }

  @Test("a scan whose connection is gone throws instead of planning", .scratchDirectory)
  func testRemotePlanningWithoutConnection() async throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("R2.astrostack"))
    defer { try? project.close() }
    let planning = ImportPlanning.remotePlanning(
      store: project.store,
      index: LibraryIndex(store: project.store, folder: try ScratchDirectory.url),
      client: { _ in nil })
    let target = RemoteImportTarget(connectionID: Self.connection, bucket: "astro", prefix: "")

    await #expect(throws: RemoteImportProblem.connectionMissing) {
      _ = try await planning(target, ImportRequest(paths: [target.path])) { _ in }
    }
  }

  @Test("a cache this build cannot read costs reads, never the scan", .scratchDirectory)
  func testUnreadableCacheIsIgnored() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("R3.astrostack"))
    defer { try? project.close() }
    let target = RemoteImportTarget(connectionID: Self.connection, bucket: "astro", prefix: "x")
    try project.store.setRemoteScan(Data("{\"from\":\"a newer build\"}".utf8), of: target.path)

    #expect(ImportPlanning.cachedScan(project.store, of: target).entries.isEmpty)
    #expect(ImportPlanning.cachedScan(nil, of: target).entries.isEmpty, "no project, no cache")
  }
}
