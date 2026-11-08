import AstroStackApp
import Foundation
import ProjectKit
import RemoteKit
import StackKit
import Testing

/// Card 0185 review: a refused connection never hides a working one to the same bucket, and a
/// run looks up only the connections of the buckets its frames are read from.
extension S3ClientLookupTests {
  @Test(
    "one bucket, a refused connection and a working one: the bucket reads, whatever the order",
    arguments: [true, false])
  func testWorkingConnectionWinsOverARefusedOne(refusedFirst: Bool) async throws {
    let refusal = S3ConnectionStore.Refusal.keychain(KeychainError(status: -25293))
    let (refused, working) = (UUID(), UUID())
    let client = try RunStoresTests.client()
    var sources = [
      RunStoresTests.source(1, bucket: "astro", connection: refused.uuidString),
      RunStoresTests.source(2, bucket: "astro", connection: working.uuidString),
    ]
    if !refusedFirst { sources.reverse() }

    let buckets = await ImportPlanning.runStores(
      sources,
      client: { id in
        guard id == refused else { return client }
        throw refusal
      })

    #expect(buckets.stores.map(\.bucket) == ["astro"])
    #expect(buckets.refusals.isEmpty)
  }

  @Test("a run asks for the connections of the buckets its frames are read from, no others")
  func testSourcesReadByInventory() {
    func light(_ path: String) -> CaptureFrame {
      var frame = CaptureFrame(path: path)
      frame.type = .light
      return frame
    }
    let astro = RunStoresTests.source(1, bucket: "astro")
    let other = RunStoresTests.source(2, bucket: "other")
    var local = Inventory(root: "/c", frames: [light("/c/l_1.fits")])
    local.regroup()
    var remote = Inventory(
      root: "s3://astro/M31", frames: [light("/c/l_1.fits"), light("s3://astro/M31/l_2.fits")])
    remote.regroup()

    #expect(RunBuckets.sources([astro, other], readBy: local).isEmpty, "a local run asks nothing")
    #expect(RunBuckets.sources([astro, other], readBy: remote).map(\.bucket) == ["astro"])
  }

  @Test("a bucket name the connection cannot address is refused before Siril, in its own words")
  func testUnaddressableBucketIsRefused() async throws {
    let https = S3Client(
      endpoint: try S3Endpoint(
        url: try #require(URL(string: "https://s3.example.com")), region: "eu-west-3",
        addressing: .virtualHost),
      credentials: S3Credentials(accessKey: "AK", secretKey: "secret"),
      transport: HTTPTransport(
        send: { _ in HTTPResponse(status: 200, headers: [:], body: Data()) },
        download: { _, _, _ in HTTPResponse(status: 200, headers: [:], body: Data()) }))
    let sources = [RunStoresTests.source(1, bucket: "my.bucket")]

    let buckets = await ImportPlanning.runStores(sources, client: { _ in https })

    #expect(buckets.stores.isEmpty)
    let refusal = try #require(buckets.refusal(reading: ["s3://my.bucket/M31/l.fits"]))
    guard case S3Error.invalidBucket(let name, _) = refusal else {
      Issue.record("not invalidBucket: \(refusal)")
      return
    }
    #expect(name == "my.bucket")
  }

  @Test("a master rebuild asks for the connections of the buckets its frames are read from")
  func testSourcesReadingPaths() {
    let astro = RunStoresTests.source(1, bucket: "astro")
    let other = RunStoresTests.source(2, bucket: "other")

    #expect(RunBuckets.sources([astro, other], reading: ["/c/l_1.fits"]).isEmpty)
    #expect(
      RunBuckets.sources([astro, other], reading: ["/c/l_1.fits", "s3://other/M31/f.fits"])
        .map(\.bucket) == ["other"])
  }
}
