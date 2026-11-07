import Foundation
import RemoteKit
import TestSupport
import Testing

/// Card 0185: an upload asked never to replace an object carries `If-None-Match: *`, so the
/// service itself refuses an overwrite a write-only key could not see coming (HEAD answers 403).
extension S3ClientTests {
  struct NoOverwriteRow: Sendable, CustomTestStringConvertible {
    let multipart: Bool
    var testDescription: String { multipart ? "multipart" : "single PUT" }
    var policy: S3Client.Policy {
      multipart ? S3ClientTests.small : S3Client.Policy(multipartThreshold: 11)
    }
  }

  static let noOverwriteRows = [NoOverwriteRow(multipart: false), NoOverwriteRow(multipart: true)]

  /// The request that creates the object: the PUT, or CompleteMultipartUpload.
  static func creates(_ request: HTTPRequest) -> Bool {
    (request.method == "PUT" && request.query("partNumber") == nil)
      || (request.method == "POST" && request.query("uploadId") != nil)
  }

  @Test(
    "asked never to replace: the creating request says If-None-Match: *, the others never",
    .scratchDirectory, arguments: noOverwriteRows)
  func testUploadSaysIfNoneMatch(row: NoOverwriteRow) async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("final.tif")
    try Self.tenBytes.write(to: file)
    let fake = Self.multipartServer { request in
      request.method == "PUT" && request.query("partNumber") == nil
        ? .make(200, headers: ["etag": "\"single\""]) : nil
    }

    _ = try await fake.client(policy: row.policy)
      .upload(file: file, bucket: "exports", key: "M31/final.tif", ifNoneMatch: true)

    let requests = await fake.requests
    let creating = requests.filter(Self.creates)
    #expect(creating.count == 1)
    #expect(creating.allSatisfy { $0.headers["if-none-match"] == "*" })
    #expect(
      requests.filter { !Self.creates($0) }.allSatisfy { $0.headers["if-none-match"] == nil },
      "parts and initiation never carry the condition")
  }

  @Test("by default an upload replaces as before: no condition", .scratchDirectory)
  func testUploadWithoutConditionByDefault() async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("final.tif")
    try Self.tenBytes.write(to: file)
    let fake = Fake { _, _ in .make(200, headers: ["etag": "\"single\""]) }

    _ = try await fake.client(policy: S3Client.Policy(multipartThreshold: 11))
      .upload(file: file, bucket: "exports", key: "k")

    #expect(await fake.requests.allSatisfy { $0.headers["if-none-match"] == nil })
  }

  @Test(
    "an object already there: 412 PreconditionFailed is thrown as sent, never retried",
    .scratchDirectory, arguments: noOverwriteRows)
  func testUploadRefusesOverwriteWhenAsked(row: NoOverwriteRow) async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("final.tif")
    try Self.tenBytes.write(to: file)
    let refusal = HTTPResponse.error(
      412, code: "PreconditionFailed",
      message: "At least one of the pre-conditions you specified did not hold")
    let fake = Self.multipartServer { request in
      if Self.creates(request) { return refusal }
      // Someone else's object: another size than the ten bytes sent.
      if request.method == "HEAD" { return .make(200, headers: ["content-length": "99"]) }
      return nil
    }

    await #expect {
      _ = try await fake.client(policy: row.policy)
        .upload(file: file, bucket: "exports", key: "M31/final.tif", ifNoneMatch: true)
    } throws: { error in
      guard case S3Error.service(412, "PreconditionFailed", _, _) = error else { return false }
      return true
    }
    #expect(await fake.requests.filter(Self.creates).count == 1, "a refusal is not retried")
  }

  @Test(
    "a write-only key: the HEAD that would recognise our own object answers 403, the 412 stays",
    .scratchDirectory, arguments: noOverwriteRows)
  func testOverwriteRefusalWithAWriteOnlyKey(row: NoOverwriteRow) async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("final.tif")
    try Self.tenBytes.write(to: file)
    let fake = Self.multipartServer { request in
      if Self.creates(request) {
        return .error(412, code: "PreconditionFailed", message: "precondition")
      }
      if request.method == "HEAD" { return .make(403) }
      return nil
    }

    await #expect {
      _ = try await fake.client(policy: row.policy)
        .upload(file: file, bucket: "exports", key: "M31/final.tif", ifNoneMatch: true)
    } throws: { error in
      guard case S3Error.service(412, _, _, _) = error else { return false }
      return true
    }
  }

  /// The ETags S3 gives `tenBytes`: one PUT, and 4-byte parts (« 0123 », « 4567 », « 89 »),
  /// computed outside Swift (Python `hashlib`) so the code never checks itself.
  static let singleETag = "781e5e245d69b566979b86e28d23f2c7"
  static let multipartETag = "61e3716e3a7767581863b67c4e785584-3"

  /// A server whose creating request answers 412 and whose HEAD shows ten bytes tagged `etag`.
  static func refusingServer(headETag etag: String) -> Fake {
    multipartServer { request in
      if creates(request) {
        return .error(412, code: "PreconditionFailed", message: "precondition")
      }
      if request.method == "HEAD" {
        return .make(200, headers: ["content-length": "10", "etag": "\"\(etag)\""])
      }
      return nil
    }
  }

  @Test(
    "a 412 on the object this upload itself wrote (its answer lost) is that object",
    .scratchDirectory, arguments: noOverwriteRows)
  func testUploadOwnObjectAfterLostAnswer(row: NoOverwriteRow) async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("final.tif")
    try Self.tenBytes.write(to: file)
    // An uppercase ETag (some S3-compatible services) is the same tag.
    let etag = (row.multipart ? Self.multipartETag : Self.singleETag).uppercased()

    let object = try await Self.refusingServer(headETag: etag).client(policy: row.policy)
      .upload(file: file, bucket: "exports", key: "M31/final.tif", ifNoneMatch: true)

    #expect(object.size == 10 && object.etag.lowercased() == etag.lowercased())
  }

  @Test(
    "a 412 on another object of the same size (and part count) is never taken for ours",
    .scratchDirectory, arguments: noOverwriteRows)
  func testForeignObjectOfTheSameSizeStaysRefused(row: NoOverwriteRow) async throws {
    let file = try ScratchDirectory.url.appendingPathComponent("final.tif")
    try Self.tenBytes.write(to: file)
    let foreign =
      row.multipart ? "0f343b0931126a20f133d67c2b018a3b-3" : String(repeating: "a", count: 32)

    await #expect {
      _ = try await Self.refusingServer(headETag: foreign).client(policy: row.policy)
        .upload(file: file, bucket: "exports", key: "M31/final.tif", ifNoneMatch: true)
    } throws: { error in
      guard case S3Error.service(412, _, _, _) = error else { return false }
      return true
    }
  }

  @Test("a multipart ETag is the MD5 of the parts' binary MD5s and their count")
  func testMultipartETag() {
    let parts = ["0123", "4567", "89"].map { FileDigest.md5(Data($0.utf8)) }
    #expect(FileDigest.multipartETag(parts) == Self.multipartETag)
    #expect(
      FileDigest.multipartETag([FileDigest.md5(Data("a".utf8))])
        == "b6ff9a06b7e20bcb2858c5b8ff744aea-1")
    #expect(FileDigest.multipartETag([]) == nil)
    #expect(FileDigest.md5Hex(Self.tenBytes) == Self.singleETag)
  }
}
