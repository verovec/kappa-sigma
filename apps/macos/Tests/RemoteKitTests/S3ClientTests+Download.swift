import CryptoKit
import Foundation
import RemoteKit
import TestSupport
import Testing

extension S3ClientTests {
  static let body = Data("M31 light frame bytes".utf8)
  static let md5 = Insecure.MD5.hash(data: body).hexString
  static let sha = body.sha256Digests.base64

  struct DownloadRow: Sendable, CustomTestStringConvertible {
    let label: String
    var headers: [String: String]
    var expect: S3Object?
    var error: S3Error?
    var testDescription: String { label }
  }

  static let downloadRows: [DownloadRow] = [
    DownloadRow(label: "single-part ETag = MD5", headers: ["etag": "\"\(md5)\""]),
    DownloadRow(
      label: "listed size and ETag agree", headers: ["etag": "\"\(md5)\""],
      expect: S3Object(key: "k", size: Int64(body.count), etag: md5, lastModified: nil)),
    DownloadRow(
      label: "size differs from the listing", headers: ["etag": "\"\(md5)\""],
      expect: S3Object(key: "k", size: 99, etag: md5, lastModified: nil),
      error: .sizeMismatch(key: "k", expected: 99, actual: Int64(body.count))),
    DownloadRow(
      label: "content differs from the MD5 ETag",
      headers: ["etag": "\"00000000000000000000000000000000\""],
      error: .checksumMismatch(
        key: "k", expected: "00000000000000000000000000000000", actual: md5)),
    DownloadRow(
      label: "object rewritten since listed", headers: ["etag": "\"\(md5)\""],
      expect: S3Object(key: "k", size: Int64(body.count), etag: "old", lastModified: nil),
      error: .objectChanged(key: "k", expectedETag: "old", actualETag: md5)),
    DownloadRow(
      label: "multipart ETag, full SHA-256 checksum",
      headers: ["etag": "\"abc-2\"", "x-amz-checksum-sha256": sha]),
    DownloadRow(
      label: "multipart ETag, wrong SHA-256 checksum",
      headers: ["etag": "\"abc-2\"", "x-amz-checksum-sha256": "AAAA"],
      error: .checksumMismatch(key: "k", expected: "AAAA", actual: sha)),
    DownloadRow(
      label: "multipart ETag, composite checksum: size only",
      headers: ["etag": "\"abc-2\"", "x-amz-checksum-sha256": "AAAA-2"]),
    DownloadRow(
      label: "SSE-C: the ETag is not an MD5",
      headers: [
        "etag": "\"11111111111111111111111111111111\"",
        "x-amz-server-side-encryption-customer-algorithm": "AES256",
      ]),
    DownloadRow(
      label: "a full SHA-256 checksum wins over a non-MD5 single-part ETag",
      headers: [
        "etag": "\"11111111111111111111111111111111\"", "x-amz-checksum-sha256": sha,
      ]),
    DownloadRow(
      label: "SSE-S3 (AES256): the ETag is still the MD5",
      headers: [
        "etag": "\"00000000000000000000000000000000\"",
        "x-amz-server-side-encryption": "AES256",
      ],
      error: .checksumMismatch(
        key: "k", expected: "00000000000000000000000000000000", actual: md5)),
    DownloadRow(
      label: "SSE-KMS: the ETag is not an MD5",
      headers: [
        "etag": "\"11111111111111111111111111111111\"",
        "x-amz-server-side-encryption": "aws:kms",
      ]),
  ]

  @Test(
    "A download is verified in <file>.part, then renamed; a bad one leaves no file",
    .scratchDirectory, arguments: downloadRows)
  func testDownloadVerifiesAndRenames(row: DownloadRow) async throws {
    let target = try ScratchDirectory.url.appendingPathComponent("Light_001.fits")
    let fake = Fake { _, _ in HTTPResponse(status: 200, headers: row.headers, body: Self.body) }
    let events = EventLog()

    var thrown: S3Error?
    do {
      let object = try await fake.client().download(
        bucket: "astro", key: "k", to: target, expect: row.expect,
        progress: { events.append($0) })
      #expect(object.size == Int64(Self.body.count))
    } catch let error as S3Error {
      thrown = error
    }

    #expect(thrown == row.error)
    #expect(!FileManager.default.fileExists(atPath: target.appendingPathExtension("part").path))
    if row.error != nil {
      #expect(!FileManager.default.fileExists(atPath: target.path))
    } else {
      #expect(try Data(contentsOf: target) == Self.body)
      #expect(events.transferred.last == Int64(Self.body.count))
    }
    let request = try #require(await fake.requests.first)
    #expect(request.headers["x-amz-checksum-mode"] == "ENABLED")
  }

  @Test("A cancelled download leaves neither the file nor its .part", .scratchDirectory)
  func testDownload_cancelLeavesNoPart() async throws {
    let target = try ScratchDirectory.url.appendingPathComponent("Light_002.fits")
    let part = target.appendingPathExtension("part")
    let transport = HTTPTransport(
      send: { _ in .make(500) },
      download: { _, destination, _ in
        try Data("half".utf8).write(to: destination)
        throw CancellationError()
      })
    let client = S3Client(
      endpoint: try S3Endpoint(
        url: try #require(URL(string: "http://127.0.0.1:9000")), region: "us-east-1",
        addressing: .pathStyle),
      credentials: Fake.credentials, transport: transport, sleep: { _ in })

    await #expect(throws: CancellationError.self) {
      try await client.download(bucket: "astro", key: "k", to: target, expect: nil)
    }
    #expect(!FileManager.default.fileExists(atPath: part.path))
    #expect(!FileManager.default.fileExists(atPath: target.path))
  }

  @Test("A failed download keeps the S3 error and leaves no file", .scratchDirectory)
  func testDownload_serviceError() async throws {
    let target = try ScratchDirectory.url.appendingPathComponent("Light_003.fits")
    let fake = Fake { _, _ in .error(404, code: "NoSuchKey", message: "gone") }

    await #expect(
      throws: S3Error.service(status: 404, code: "NoSuchKey", message: "gone", requestID: "R1")
    ) {
      try await fake.client().download(bucket: "astro", key: "k", to: target, expect: nil)
    }
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(!FileManager.default.fileExists(atPath: target.appendingPathExtension("part").path))
  }
}
