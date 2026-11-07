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

  /// The parts of `tenBytes` in 4-byte parts, each tagged with its own MD5 as S3 does.
  static let partTags = ["0123", "4567", "89"].map { FileDigest.md5Hex(Data($0.utf8)) }

  /// A server whose parts answer their MD5, whose creating request answers 412, and whose HEAD
  /// shows ten bytes tagged `etag`.
  static func refusingServer(headETag etag: String) -> Fake {
    multipartServer { request in
      if creates(request) {
        return .error(412, code: "PreconditionFailed", message: "precondition")
      }
      if let part = request.query("partNumber").flatMap(Int.init) {
        return .make(200, headers: ["etag": "\"\(partTags[part - 1])\""])
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
    let etag =
      row.multipart
      ? try #require(FileDigest.multipartETag(Self.partTags)) : FileDigest.md5Hex(Self.tenBytes)

    let object = try await Self.refusingServer(headETag: etag).client(policy: row.policy)
      .upload(file: file, bucket: "exports", key: "M31/final.tif", ifNoneMatch: true)

    #expect(object.size == 10 && object.etag == etag)
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

  struct ETagRow: Sendable, CustomTestStringConvertible {
    let parts: [String]
    let expected: String?
    var testDescription: String { "\(parts.count) parts → \(expected ?? "nil")" }
  }

  @Test(
    "a multipart ETag is the MD5 of the parts' binary MD5s and their count; else nothing",
    arguments: [
      // md5(md5("a")) — the one-part case of the AWS rule, checked by hand.
      ETagRow(
        parts: ["0cc175b9c0f1b6a831c399e269772661"],
        expected: FileDigest.md5Hex(
          Data([
            0x0c, 0xc1, 0x75, 0xb9, 0xc0, 0xf1, 0xb6, 0xa8, 0x31, 0xc3, 0x99, 0xe2, 0x69, 0x77,
            0x26,
            0x61,
          ])) + "-1"),
      ETagRow(parts: [], expected: nil),
      ETagRow(parts: ["p1"], expected: nil),
      ETagRow(parts: [String(repeating: "z", count: 32)], expected: nil),
    ])
  func testMultipartETag(row: ETagRow) {
    #expect(FileDigest.multipartETag(row.parts) == row.expected)
  }
}
