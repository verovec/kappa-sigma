import Foundation
import RemoteKit
import Testing

/// Card 0184: a bucket name that cannot be addressed is refused before any request, and only
/// where it would really fail: path-style stays as permissive as the server it talks to.
@Suite("S3 endpoints refuse bucket names they cannot address")
struct S3EndpointTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let bucket: String
    let url: String
    let addressing: S3Endpoint.Addressing
    /// `nil` = accepted; otherwise a word the refusal's reason must contain.
    let refusal: String?
    var testDescription: String { "\(bucket) · \(url) · \(addressing)" }
  }

  static let rows = [
    Row(
      bucket: "captures", url: "https://s3.amazonaws.com", addressing: .virtualHost, refusal: nil),
    Row(
      bucket: "m31-2026", url: "https://s3.amazonaws.com", addressing: .virtualHost, refusal: nil),
    // Dots are legal names, but `*.s3.amazonaws.com` covers one label: TLS fails over https.
    Row(
      bucket: "astro.data", url: "https://s3.amazonaws.com", addressing: .virtualHost,
      refusal: "path-style"),
    Row(bucket: "astro.data", url: "http://minio.lan:9000", addressing: .virtualHost, refusal: nil),
    Row(
      bucket: "astro.data", url: "https://s3.amazonaws.com", addressing: .pathStyle, refusal: nil),
    // Not a host name: uppercase, underscore, too short, too long, a hyphen at an edge, `..`.
    Row(
      bucket: "Astro", url: "https://s3.amazonaws.com", addressing: .virtualHost,
      refusal: "path-style"),
    Row(
      bucket: "astro_data", url: "https://r2.example", addressing: .virtualHost,
      refusal: "path-style"),
    Row(
      bucket: "ab", url: "https://s3.amazonaws.com", addressing: .virtualHost, refusal: "path-style"
    ),
    Row(
      bucket: String(repeating: "a", count: 64), url: "https://s3.amazonaws.com",
      addressing: .virtualHost, refusal: "path-style"),
    Row(
      bucket: "-astro", url: "https://s3.amazonaws.com", addressing: .virtualHost,
      refusal: "path-style"),
    Row(bucket: "a..b", url: "http://minio.lan", addressing: .virtualHost, refusal: "path-style"),
    // Path-style: whatever the server accepts (MinIO, Garage), except what changes the path.
    Row(bucket: "Astro_Data", url: "http://127.0.0.1:9000", addressing: .pathStyle, refusal: nil),
    Row(bucket: "ab", url: "http://127.0.0.1:9000", addressing: .pathStyle, refusal: nil),
    Row(bucket: "", url: "http://127.0.0.1:9000", addressing: .pathStyle, refusal: "required"),
    Row(bucket: "", url: "https://s3.amazonaws.com", addressing: .virtualHost, refusal: "required"),
    Row(bucket: "astro/M31", url: "http://127.0.0.1:9000", addressing: .pathStyle, refusal: "/"),
  ]

  @Test("bucket names: valid, refused with the reason, or left to the server", arguments: rows)
  func testBucketNameValidation(row: Row) throws {
    let endpoint = try S3Endpoint(
      url: try #require(URL(string: row.url)), region: "us-east-1", addressing: row.addressing)
    do {
      try endpoint.validate(bucket: row.bucket)
      #expect(row.refusal == nil, "accepted, expected a refusal")
    } catch let error as S3Error {
      guard case .invalidBucket(let name, let reason) = error else {
        Issue.record("unexpected \(error)")
        return
      }
      let refusal = try #require(row.refusal, "refused: \(error)")
      #expect(name == row.bucket)
      #expect(reason.contains(refusal), "reason: \(reason)")
      #expect(error.description.contains(reason))
      #expect(!S3Error.isRetryable(error))
    }
  }

  @Test("a refused bucket sends nothing")
  func testRefusedBeforeAnyRequest() async throws {
    let fake = Fake { _, _ in .make(200) }
    let client = try fake.client()

    await #expect(throws: S3Error.self) {
      _ = try await client.head(bucket: "astro/M31", key: "a.fits")
    }

    #expect(await fake.requests.isEmpty)
  }
}
