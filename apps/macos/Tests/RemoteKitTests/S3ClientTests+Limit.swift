import Foundation
import RemoteKit
import TestSupport
import Testing

extension S3ClientTests {
  @Test("A limited listing asks for max-keys and stops once it has enough (card 0150's Test)")
  func testList_limitStopsEarly() async throws {
    let fake = Fake { _, _ in
      .make(
        200,
        Self.listing(
          [("M31/a.fits", 1, "e1"), ("M31/b.fits", 2, "e2"), ("M31/c.fits", 3, "e3")],
          truncated: true, next: "more"))
    }

    let objects = try await fake.client().list(bucket: "astro", prefix: "M31/", limit: 2)

    #expect(objects.map(\.key) == ["M31/a.fits", "M31/b.fits"])
    let requests = await fake.requests
    #expect(requests.count == 1, "no second page once the limit is reached")
    #expect(requests.first?.query("max-keys") == "2")
  }

  @Test("A limit of zero or less lists nothing and sends nothing", arguments: [0, -3])
  func testList_nonPositiveLimit(limit: Int) async throws {
    let fake = Fake { _, _ in .make(500) }

    let objects = try await fake.client().list(bucket: "astro", prefix: "", limit: limit)

    #expect(objects.isEmpty)
    #expect(await fake.requests.isEmpty)
  }

  @Test("Every S3Error reads as one line naming what to act on")
  func testErrorDescriptions() {
    let errors: [S3Error] = [
      .service(status: 404, code: nil, message: nil, requestID: nil),
      .invalidEndpoint("ftp://h"), .invalidRequest("u"), .invalidResponse("r"),
      .sizeMismatch(key: "k", expected: 2, actual: 1),
      .checksumMismatch(key: "k", expected: "a", actual: "b"),
      .objectChanged(key: "k", expectedETag: "a", actualETag: "b"),
    ]
    let lines = errors.map(\.description)
    #expect(lines[0] == "S3 404")
    #expect(Set(lines).count == errors.count)
    #expect(lines.dropFirst(4).allSatisfy { $0.hasPrefix("k") })
  }
}

extension S3ClientTests {
  @Test("CreateMultipartUpload without UploadId stops before any part", .scratchDirectory)
  func testUpload_initiateWithoutUploadID() async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("stack.fit")
    try Data("0123456789".utf8).write(to: file)
    let fake = Fake { _, _ in .make(200, "<InitiateMultipartUploadResult/>") }

    await #expect(
      throws: S3Error.invalidResponse("CreateMultipartUpload without UploadId")
    ) {
      try await fake.client(policy: S3Client.Policy(multipartThreshold: 1, partSize: 4))
        .upload(file: file, bucket: "b", key: "k")
    }
    #expect(await fake.requests.count == 1)
  }
}
