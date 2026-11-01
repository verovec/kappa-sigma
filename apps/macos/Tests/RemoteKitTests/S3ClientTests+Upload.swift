import Foundation
import RemoteKit
import TestSupport
import Testing

extension S3ClientTests {
  /// Ten bytes in 4-byte parts: three parts (4, 4, 2).
  static let small = S3Client.Policy(multipartThreshold: 10, partSize: 4)
  static let tenBytes = Data("0123456789".utf8)

  static let initiate =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><InitiateMultipartUploadResult>"
    + "<Bucket>astro</Bucket><Key>k</Key><UploadId>up-1</UploadId></InitiateMultipartUploadResult>"

  /// A multipart server: initiate, parts answered `"p<n>"`, complete; `failing` scripts a call.
  static func multipartServer(failing: (@Sendable (HTTPRequest) throws -> HTTPResponse?)? = nil)
    -> Fake
  {
    Fake { request, _ in
      if let answer = try failing?(request) { return answer }
      switch (request.method, request.query("uploads"), request.query("partNumber")) {
      case ("POST", .some, _): return .make(200, initiate)
      case ("PUT", _, .some(let part)): return .make(200, headers: ["etag": "\"p\(part)\""])
      case ("POST", .none, _):
        return .make(
          200,
          "<CompleteMultipartUploadResult><ETag>&quot;whole-3&quot;</ETag>"
            + "</CompleteMultipartUploadResult>")
      default: return .make(204)
      }
    }
  }

  @Test("Below the threshold: one PUT with its SHA-256 checksum", .scratchDirectory)
  func testUploadSingleBelowThreshold() async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("final.tif")
    try Self.tenBytes.write(to: file)
    let fake = Fake { _, _ in .make(200, headers: ["etag": "\"single\""]) }

    let object = try await fake.client(policy: S3Client.Policy(multipartThreshold: 11))
      .upload(file: file, bucket: "exports", key: "M31/final.tif")

    #expect(object == S3Object(key: "M31/final.tif", size: 10, etag: "single", lastModified: nil))
    let requests = await fake.requests
    #expect(requests.map(\.method) == ["PUT"])
    #expect(requests[0].body == Self.tenBytes)
    #expect(requests[0].headers["x-amz-checksum-sha256"] == Self.tenBytes.sha256Digests.base64)
    #expect(requests[0].headers["x-amz-content-sha256"] == Self.tenBytes.sha256Hex)
    #expect(requests[0].headers["content-type"] == "application/octet-stream")
  }

  @Test(
    "From the threshold: initiate, checksummed parts, complete listing every part",
    .scratchDirectory)
  func testUploadMultipartPartsAndChecksums() async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("stack.fit")
    try Self.tenBytes.write(to: file)
    let fake = Self.multipartServer()
    let events = EventLog()

    let object = try await fake.client(policy: Self.small).upload(
      file: file, bucket: "exports", key: "k", progress: { events.append($0) })

    #expect(object.etag == "whole-3")
    let requests = await fake.requests
    #expect(requests.map(\.method) == ["POST", "PUT", "PUT", "PUT", "POST"])
    #expect(requests[0].headers["x-amz-checksum-algorithm"] == "SHA256")
    #expect(requests[0].headers["content-type"] == "application/octet-stream")
    let parts = Array(requests[1...3])
    let chunks = [Data("0123".utf8), Data("4567".utf8), Data("89".utf8)]
    #expect(parts.map { $0.query("partNumber") } == ["1", "2", "3"])
    #expect(parts.map { $0.query("uploadId") } == ["up-1", "up-1", "up-1"])
    #expect(parts.map(\.body) == chunks)
    #expect(
      parts.map { $0.headers["x-amz-checksum-sha256"] } == chunks.map { $0.sha256Digests.base64 })
    #expect(requests[4].query("uploadId") == "up-1")
    #expect(requests[4].headers["content-type"] == "application/xml")
    let complete = String(bytes: requests[4].body ?? Data(), encoding: .utf8) ?? ""
    for (number, chunk) in zip(1..., chunks) {
      #expect(
        complete.contains(
          "<Part><PartNumber>\(number)</PartNumber><ETag>\"p\(number)\"</ETag>"
            + "<ChecksumSHA256>\(chunk.sha256Digests.base64)</ChecksumSHA256></Part>"))
    }
    #expect(events.transferred == [4, 8, 10])
  }

  struct AbortRow: Sendable, CustomTestStringConvertible {
    let label: String
    let failing: @Sendable (HTTPRequest) throws -> HTTPResponse?
    var testDescription: String { label }
  }

  static let abortRows: [AbortRow] = [
    AbortRow(label: "a part answered without ETag") { request in
      request.query("partNumber") == "2" ? .make(200) : nil
    },
    AbortRow(label: "a part refused") { request in
      request.query("partNumber") == "2" ? .error(403, code: "AccessDenied", message: "no") : nil
    },
    AbortRow(label: "cancelled between parts") { request in
      if request.query("partNumber") == "2" { throw CancellationError() }
      return nil
    },
    AbortRow(label: "complete answers 200 with an <Error>") { request in
      request.method == "POST" && request.query("uploads") == nil
        ? .make(200, "<Error><Code>InternalError</Code><Message>late</Message></Error>") : nil
    },
  ]

  @Test(
    "A failed or cancelled multipart upload is aborted", .scratchDirectory,
    arguments: abortRows)
  func testUploadAbortsOnFailure(row: AbortRow) async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("stack.fit")
    try Self.tenBytes.write(to: file)
    let fake = Self.multipartServer(failing: row.failing)

    await #expect(throws: (any Error).self) {
      try await fake.client(policy: Self.small).upload(file: file, bucket: "exports", key: "k")
    }

    let last = try #require(await fake.requests.last)
    #expect(last.method == "DELETE")
    #expect(last.query("uploadId") == "up-1")
  }

  @Test(
    "A 200 InternalError from CompleteMultipartUpload is retried, the parts kept",
    .scratchDirectory)
  func testUpload_completeErrorIsRetried() async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("stack.fit")
    try Self.tenBytes.write(to: file)
    let completes = Counter()
    let fake = Self.multipartServer { request in
      guard request.method == "POST", request.query("uploads") == nil,
        completes.next() == 0
      else { return nil }
      return .make(200, "<Error><Code>InternalError</Code><Message>late</Message></Error>")
    }
    let events = EventLog()

    let object = try await fake.client(policy: Self.small).upload(
      file: file, bucket: "exports", key: "k", progress: { events.append($0) })

    #expect(object.etag == "whole-3")
    #expect(await fake.requests.map(\.method) == ["POST", "PUT", "PUT", "PUT", "POST", "POST"])
    #expect(events.retries == [1])
  }

  struct LostCompleteRow: Sendable, CustomTestStringConvertible {
    let label: String
    let head: HTTPResponse
    let succeeds: Bool
    var testDescription: String { label }
  }

  static let lostCompleteRows: [LostCompleteRow] = [
    LostCompleteRow(
      label: "the object is whole: the upload succeeded",
      head: .make(200, headers: ["content-length": "10", "etag": "\"whole-3\""]), succeeds: true),
    LostCompleteRow(
      label: "an older object of another size: failure",
      head: .make(200, headers: ["content-length": "7", "etag": "\"old\""]), succeeds: false),
    LostCompleteRow(label: "no object: failure", head: .make(404), succeeds: false),
  ]

  @Test(
    "A Complete whose answer was lost, then NoSuchUpload, checks the object with HEAD",
    .scratchDirectory, arguments: lostCompleteRows)
  func testUpload_lostCompleteAnswer(row: LostCompleteRow) async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("stack.fit")
    try Self.tenBytes.write(to: file)
    let completes = Counter()
    let fake = Self.multipartServer { request in
      if request.method == "HEAD" { return row.head }
      guard request.method == "POST", request.query("uploads") == nil else { return nil }
      if completes.next() == 0 { throw URLError(.networkConnectionLost) }
      return .error(404, code: "NoSuchUpload", message: "gone")
    }

    let object = try? await fake.client(policy: Self.small).upload(
      file: file, bucket: "exports", key: "k")

    #expect((object != nil) == row.succeeds)
    let methods = await fake.requests.map(\.method)
    #expect(methods.contains("HEAD"))
    #expect(methods.last == (row.succeeds ? "HEAD" : "DELETE"))
  }
}
