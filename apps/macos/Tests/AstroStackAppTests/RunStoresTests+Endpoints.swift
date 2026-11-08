import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import Testing

/// Card 0186: a bucket name is one bucket per endpoint. Two sources naming it through connections
/// on different endpoints are two buckets the run cannot tell apart (frames, scan cache and
/// stager are keyed by name): the run is refused with both hosts named, never fed from one.
@Suite("Run buckets — one bucket name, one endpoint")
struct RunStoresEndpointTests {
  static func client(_ url: String) throws -> S3Client {
    S3Client(
      endpoint: try S3Endpoint(
        url: try #require(URL(string: url)), region: "us-east-1", addressing: .pathStyle),
      credentials: S3Credentials(accessKey: "AK", secretKey: "secret"),
      transport: HTTPTransport(
        send: { _ in HTTPResponse(status: 200, headers: [:], body: Data()) },
        download: { _, _, _ in HTTPResponse(status: 200, headers: [:], body: Data()) }))
  }

  @Test(
    "two connections naming one bucket: same endpoint reads it, two endpoints refuse it",
    arguments: [
      ("http://127.0.0.1:9000", "http://127.0.0.1:9000", false),
      ("http://127.0.0.1:9000", "https://s3.example.org", true),
    ])
  func testOneBucketNameTwoEndpoints(first: String, second: String, refused: Bool) async throws {
    let one = UUID()
    let two = UUID()
    let clients = [one: try Self.client(first), two: try Self.client(second)]
    let sources = [
      RunStoresTests.source(1, bucket: "astro", connection: one.uuidString),
      RunStoresTests.source(2, bucket: "astro", prefix: "M45", connection: two.uuidString),
    ]

    let buckets = await ImportPlanning.runStores(sources, client: { clients[$0] })

    #expect(buckets.stores.isEmpty == refused, "\(buckets.stores.map(\.bucket))")
    let refusal = buckets.refusal(reading: ["s3://astro/M31/l_1.fits"])
    #expect((refusal != nil) == refused)
    if let refusal {
      #expect(
        refusal as? RemoteImportProblem
          == .bucketOnTwoEndpoints(bucket: "astro", hosts: ["127.0.0.1:9000", "s3.example.org"]))
    }
  }
}
