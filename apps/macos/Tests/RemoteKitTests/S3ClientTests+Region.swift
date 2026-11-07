import Foundation
import RemoteKit
import TestSupport
import Testing

/// Card 0184: a bucket in another region is said with that region, never a bare « S3 301 ».
@Suite("S3Client says which region a bucket is in")
struct S3ClientRegionTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let label: String
    let response: HTTPResponse
    /// `nil` = stays a `.service` error with this status.
    let actual: String?
    let status: Int
    var testDescription: String { label }
  }

  static let redirect = HTTPResponse.make(
    301, headers: ["x-amz-bucket-region": "eu-west-3", "x-amz-request-id": "R1"])
  static let malformed = HTTPResponse(
    status: 400, headers: ["x-amz-bucket-region": "eu-west-3"],
    body: Data(
      ("<Error><Code>AuthorizationHeaderMalformed</Code><Message>the region 'us-east-1' is "
        + "wrong; expecting 'eu-west-3'</Message><Region>eu-west-3</Region></Error>").utf8))

  static let denied = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>"

  static let rows = [
    Row(
      label: "HEAD 301 with the bucket's region", response: redirect, actual: "eu-west-3",
      status: 301),
    Row(
      label: "400 AuthorizationHeaderMalformed", response: malformed, actual: "eu-west-3",
      status: 400),
    Row(
      label: "307 TemporaryRedirect",
      response: .make(307, headers: ["x-amz-bucket-region": "eu-west-3"]),
      actual: "eu-west-3", status: 307),
    Row(
      label: "301 without the header stays a 301", response: .make(301), actual: nil, status: 301),
    Row(
      label: "403 in the right region stays the service's answer",
      response: HTTPResponse(
        status: 403, headers: ["x-amz-bucket-region": "us-east-1"],
        body: Data(Self.denied.utf8)),
      actual: nil, status: 403),
    Row(
      label: "a 403 naming another region is not a region problem",
      response: .make(403, headers: ["x-amz-bucket-region": "eu-west-3"]),
      actual: nil, status: 403),
  ]

  @Test("the region is said when the answer names another one", arguments: rows)
  func testWrongRegionIsSaid(row: Row) async throws {
    let fake = Fake { _, _ in row.response }

    do {
      _ = try await fake.client().head(bucket: "astro", key: "M31/a.fits")
      Issue.record("expected an error")
    } catch let error as S3Error {
      if let actual = row.actual {
        #expect(
          error
            == .wrongRegion(
              status: row.status, bucket: "astro", expected: "us-east-1", actual: actual))
        #expect(error.description.contains("eu-west-3"))
        #expect(error.description.contains("us-east-1"))
        #expect(error.description.hasPrefix("S3 \(row.status)"))
      } else {
        guard case .service(let status, _, _, _) = error else {
          Issue.record("expected a service error, got \(error)")
          return
        }
        #expect(status == row.status)
      }
      #expect(!S3Error.isRetryable(error))
    }
    // Never followed, never retried: one request.
    #expect(await fake.requests.count == 1)
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
        status: 301, bucket: "astro", expected: "us-east-1", actual: "eu-west-3")
    ) {
      _ = try await fake.client().download(
        bucket: "astro", key: "M31/a.fits", to: destination, expect: nil)
    }
  }
}
