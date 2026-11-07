import Foundation
import RemoteKit
import TestSupport
import Testing

/// Card 0184: a bucket in another region is said with that region, never a bare « S3 301 »,
/// and the service's own answer stays in front.
@Suite("S3Client says which region a bucket is in")
struct S3ClientRegionTests {
  enum Outcome: Sendable, Equatable {
    /// `wrongRegion` naming `region`; `ending` is the advice the description ends with.
    case region(String, ending: String)
    /// The service's error with this status, after `tries` requests.
    case service(status: Int, tries: Int)
  }

  struct Row: Sendable, CustomTestStringConvertible {
    let label: String
    let response: HTTPResponse
    let outcome: Outcome
    var testDescription: String { label }
  }

  static let denied = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>"
  static let redirect = HTTPResponse.make(
    301, headers: ["x-amz-bucket-region": "eu-west-3", "x-amz-request-id": "R1"])

  static func error(_ status: Int, _ code: String, region: String) -> HTTPResponse {
    HTTPResponse(
      status: status, headers: ["x-amz-bucket-region": region],
      body: Data("<Error><Code>\(code)</Code><Message>m</Message></Error>".utf8))
  }

  static let other = "the connection says us-east-1"
  static let endpoint = "which 127.0.0.1:9000 does not serve: use that region's endpoint"

  static let rows = [
    Row(
      label: "HEAD 301 with the bucket's region", response: redirect,
      outcome: .region("eu-west-3", ending: other)),
    Row(
      label: "400 AuthorizationHeaderMalformed",
      response: error(400, "AuthorizationHeaderMalformed", region: "eu-west-3"),
      outcome: .region("eu-west-3", ending: other)),
    Row(
      label: "307 TemporaryRedirect",
      response: .make(307, headers: ["x-amz-bucket-region": "eu-west-3"]),
      outcome: .region("eu-west-3", ending: other)),
    Row(
      label: "301 naming the connection's own region: the endpoint is the problem",
      response: .make(301, headers: ["x-amz-bucket-region": "us-east-1"]),
      outcome: .region("us-east-1", ending: endpoint)),
    Row(
      label: "HEAD 400 without a body, another region named",
      response: .make(400, headers: ["x-amz-bucket-region": "eu-west-3"]),
      outcome: .region("eu-west-3", ending: other)),
    Row(
      label: "307 in the connection's own region is S3's transient redirect",
      response: .make(307, headers: ["x-amz-bucket-region": "us-east-1"]),
      outcome: .service(status: 307, tries: 1)),
    Row(
      label: "301 without the header stays a 301", response: .make(301),
      outcome: .service(status: 301, tries: 1)),
    Row(
      label: "403 with the header stays the service's answer",
      response: error(403, "AccessDenied", region: "eu-west-3"),
      outcome: .service(status: 403, tries: 1)),
    Row(
      label: "400 RequestTimeout with the header stays retried",
      response: error(400, "RequestTimeout", region: "eu-west-3"),
      outcome: .service(status: 400, tries: 3)),
    Row(
      label: "400 InvalidArgument with the header is not a region problem",
      response: error(400, "InvalidArgument", region: "eu-west-3"),
      outcome: .service(status: 400, tries: 1)),
  ]

  @Test("the region is said when the answer names it", arguments: rows)
  func testWrongRegionIsSaid(row: Row) async throws {
    let fake = Fake { _, _ in row.response }

    do {
      _ = try await fake.client().head(bucket: "astro", key: "M31/a.fits")
      Issue.record("expected an error")
    } catch let error as S3Error {
      switch row.outcome {
      case .region(let region, let ending):
        guard case .wrongRegion(let bucket, let named, let connection, _, let answer) = error else {
          Issue.record("expected wrongRegion, got \(error)")
          return
        }
        #expect(bucket == "astro" && named == region && connection == "us-east-1")
        // The service's own words first (R2), then what to change.
        #expect(error.description.hasPrefix(answer.description))
        #expect(answer.description.hasPrefix("S3 \(row.response.status)"))
        #expect(error.description.hasSuffix(ending))
        #expect(!S3Error.isRetryable(error))
        #expect(await fake.requests.count == 1)
      case .service(let status, let tries):
        guard case .service(let got, _, _, _) = error else {
          Issue.record("expected a service error, got \(error)")
          return
        }
        #expect(got == status)
        #expect(await fake.requests.count == tries)
      }
    }
  }

  @Test("a 301 without the header keeps today's words")
  func testRedirectWithoutRegionStaysA301() async throws {
    let fake = Fake { _, _ in .make(301) }

    await #expect(throws: S3Error.service(status: 301, code: nil, message: nil, requestID: nil)) {
      _ = try await fake.client().list(bucket: "astro", prefix: "M31/")
    }
  }

  @Test("a download in the wrong region is said the same way", .scratchDirectory)
  func testDownloadWrongRegion() async throws {
    let fake = Fake { _, _ in Self.redirect }
    let destination = try ScratchDirectory.url.appendingPathComponent("a.fits")

    await #expect(
      throws: S3Error.wrongRegion(
        bucket: "astro", region: "eu-west-3", connection: "us-east-1", host: "127.0.0.1:9000",
        answer: .service(status: 301, code: nil, message: nil, requestID: "R1"))
    ) {
      _ = try await fake.client().download(
        bucket: "astro", key: "M31/a.fits", to: destination, expect: nil)
    }
  }
}
