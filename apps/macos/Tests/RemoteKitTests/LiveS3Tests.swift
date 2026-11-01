import CryptoKit
import Foundation
import RemoteKit
import TestSupport
import Testing

/// Where the live round trip runs: a local `minio server` named by `ASTROSTACK_S3_LIVE_ENDPOINT`
/// (`just s3-live`), never a real bucket by default.
enum LiveS3 {
  struct Configuration {
    let endpoint: S3Endpoint
    let credentials: S3Credentials
    let bucket: String
  }

  /// `nil` (the suite skips) without the endpoint variable, or under `ASTROSTACK_SKIP_LIVE=1`.
  static var configuration: Configuration? {
    let env = ProcessInfo.processInfo.environment
    guard env["ASTROSTACK_SKIP_LIVE"] != "1",
      let text = env["ASTROSTACK_S3_LIVE_ENDPOINT"], let url = URL(string: text),
      let endpoint = try? S3Endpoint(
        url: url, region: env["ASTROSTACK_S3_LIVE_REGION"] ?? "us-east-1", addressing: .pathStyle)
    else { return nil }
    return Configuration(
      endpoint: endpoint,
      credentials: S3Credentials(
        accessKey: env["ASTROSTACK_S3_LIVE_ACCESS_KEY"] ?? "minioadmin",
        secretKey: env["ASTROSTACK_S3_LIVE_SECRET_KEY"] ?? "minioadmin"),
      bucket: env["ASTROSTACK_S3_LIVE_BUCKET"] ?? "astrostack-live")
  }
}

@Suite(
  "Live S3: a real round trip against a local MinIO",
  .enabled(if: LiveS3.configuration != nil, "ASTROSTACK_S3_LIVE_ENDPOINT unset (just s3-live)"),
  .tags(.live), .serialized, .timeLimit(.minutes(5)))
struct LiveS3Tests {
  @Test(
    "Upload 70 MiB (multipart) and 1 KiB, list, head, ranged get, download, delete",
    .scratchDirectory)
  func testRoundTrip() async throws {
    let live = try #require(LiveS3.configuration)
    let transport = HTTPTransport.urlSession()
    let client = S3Client(
      endpoint: live.endpoint, credentials: live.credentials, transport: transport)
    try await Self.ensureBucket(live, transport: transport)
    let scratch = try ScratchDirectory.url
    let prefix = "astrostack-live/\(UUID().uuidString)/"
    let big = try Self.file(scratch.appendingPathComponent("big.fit"), bytes: 70 << 20)
    let small = try Self.file(scratch.appendingPathComponent("small.fit"), bytes: 1024)

    do {
      // Inside the do: a failed second upload must not leave the first one in the bucket.
      let uploaded = try await client.upload(
        file: big, bucket: live.bucket, key: prefix + "big.fit")
      _ = try await client.upload(file: small, bucket: live.bucket, key: prefix + "small.fit")
      #expect(uploaded.etag.hasSuffix("-5"))
      let listed = try await client.list(bucket: live.bucket, prefix: prefix)
      #expect(listed.map(\.key) == [prefix + "big.fit", prefix + "small.fit"])
      #expect(listed.map(\.size) == [70 << 20, 1024])

      let head = try await client.head(bucket: live.bucket, key: prefix + "big.fit")
      #expect(head?.size == 70 << 20)
      let slice = try await client.get(
        bucket: live.bucket, key: prefix + "big.fit", range: 1_000_000...1_000_999)
      #expect(slice == (try Data(contentsOf: big))[1_000_000...1_000_999])

      for (name, object) in zip(["big.fit", "small.fit"], listed) {
        let target = scratch.appendingPathComponent("down-\(name)")
        _ = try await client.download(
          bucket: live.bucket, key: object.key, to: target, expect: object)
        #expect(
          try FileDigest.sha256Base64(target)
            == FileDigest.sha256Base64(scratch.appendingPathComponent(name)))
      }
    } catch {
      Issue.record(error)
    }

    for key in [prefix + "big.fit", prefix + "small.fit"] {
      try await client.delete(bucket: live.bucket, key: key)
    }
    #expect(try await client.list(bucket: live.bucket, prefix: prefix).isEmpty)
    #expect(try await client.head(bucket: live.bucket, key: prefix + "big.fit") == nil)
  }

  /// A file of `bytes` pseudo-random bytes (seeded, so a failure reproduces).
  static func file(_ url: URL, bytes: Int) throws -> URL {
    var generator = SplitMix(state: UInt64(bytes))
    var data = Data(capacity: bytes)
    while data.count < bytes {
      withUnsafeBytes(of: generator.next()) { data.append(contentsOf: $0) }
    }
    try data.prefix(bytes).write(to: url)
    return url
  }

  /// Creates the bucket; « already owned » is fine.
  static func ensureBucket(_ live: LiveS3.Configuration, transport: HTTPTransport) async throws {
    let request = try S3Request(method: "PUT", bucket: live.bucket, key: "")
      .prepared(
        endpoint: live.endpoint,
        signer: SigV4(credentials: live.credentials, region: live.endpoint.region), date: Date())
    let response = try await transport.send(request)
    #expect(response.isSuccess || response.status == 409, "create bucket: \(response.status)")
  }

  struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }
}
