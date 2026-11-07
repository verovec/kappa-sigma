import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import TestSupport
import Testing

/// Card 0154: a run reads a remote source's frames through the connection that source's own row
/// names — and a source whose connection is gone gives the run no bucket at all, so the run
/// refuses by name instead of stacking the lanes it could read.
@Suite("Run buckets — one store per remote source, through its own connection")
struct RunStoresTests {
  static func source(
    _ id: Int64, bucket: String?, prefix: String? = "M31", connection: String? = UUID().uuidString,
    kind: ProjectSource.Kind = .remoteNight
  ) -> ProjectSource {
    ProjectSource(
      id: id, kind: kind, path: bucket.map { "s3://\($0)/\(prefix ?? "")" } ?? "/c/M31",
      readOnly: true, profileID: nil, connectionID: connection, bucket: bucket, prefix: prefix,
      createdAt: 0, updatedAt: 0)
  }

  static func client() throws -> S3Client {
    S3Client(
      endpoint: try S3Endpoint(
        url: try #require(URL(string: "http://127.0.0.1:9000")), region: "us-east-1",
        addressing: .pathStyle),
      credentials: S3Credentials(accessKey: "AK", secretKey: "secret"),
      transport: HTTPTransport(
        send: { _ in HTTPResponse(status: 200, headers: [:], body: Data()) },
        download: { _, _, _ in HTTPResponse(status: 200, headers: [:], body: Data()) }))
  }

  @Test("one store per bucket, local nights ignored, the first source of a bucket deciding")
  func testOneStorePerBucket() async throws {
    let client = try Self.client()
    let sources = [
      Self.source(1, bucket: "astro"),
      Self.source(2, bucket: "astro", prefix: "M45"),
      Self.source(3, bucket: "other"),
      Self.source(4, bucket: nil, kind: .night),
    ]

    let stores = await ImportPlanning.runStores(sources, client: { _ in client }).stores

    #expect(stores.map(\.bucket) == ["astro", "other"], "one per bucket, in name order")
  }

  @Test("a source whose connection is gone gives no bucket: the run refuses by name")
  func testMissingConnectionGivesNoBucket() async throws {
    let sources = [Self.source(1, bucket: "astro")]

    #expect(await ImportPlanning.runStores(sources, client: { _ in nil }).stores.isEmpty)
    #expect(
      await ImportPlanning.runStores(
        [Self.source(2, bucket: "astro", connection: "not-a-uuid")], client: { _ in nil }
      ).stores.isEmpty, "a row written without a usable connection id is no bucket either")
  }

  @Test("a project of folders alone gives a run no bucket at all")
  func testLocalProjectHasNoBuckets() async throws {
    let client = try Self.client()

    #expect(
      await ImportPlanning.runStores(
        [Self.source(1, bucket: nil, kind: .night)], client: { _ in client }
      ).stores.isEmpty)
    #expect(await ImportPlanning.runStores([], client: { _ in client }).stores.isEmpty)
  }
}
