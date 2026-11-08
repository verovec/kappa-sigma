import Foundation
import RemoteKit
import TestSupport
import Testing

extension LiveS3Tests {
  /// How an upload reaches the service: one PUT, or parts (5 MiB is S3's smallest part).
  enum Shape: String, CaseIterable, Sendable {
    case single, multipart

    var bytes: Int { self == .single ? 1024 : 11 << 20 }
    var policy: S3Client.Policy {
      self == .single
        ? S3Client.Policy() : S3Client.Policy(multipartThreshold: 6 << 20, partSize: 5 << 20)
    }
  }

  @Test(
    "An upload that may not replace: another object is refused (412), our own resent is returned",
    .scratchDirectory, arguments: Shape.allCases)
  func testNoOverwrite(_ shape: Shape) async throws {
    let live = try #require(LiveS3Environment.current)
    let scratch = try ScratchDirectory.url
    let ours = try Self.file(scratch.appendingPathComponent("ours.fit"), bytes: shape.bytes)
    let other = try Self.file(scratch.appendingPathComponent("other.fit"), bytes: shape.bytes + 1)

    try await live.withRun { base, prefix in
      let client = S3Client(
        endpoint: live.endpoint, credentials: live.credentials, transport: .urlSession(),
        policy: shape.policy)
      let key = prefix + "x.fit"
      let written = try await client.upload(
        file: ours, bucket: live.bucket, key: key, ifNoneMatch: true)
      if shape == .multipart { #expect(written.etag.hasSuffix("-3")) }

      // A retry after a lost answer meets its own object: recognised, not refused.
      let resent = try await client.upload(
        file: ours, bucket: live.bucket, key: key, ifNoneMatch: true)
      #expect(resent.etag == written.etag)

      await #expect {
        _ = try await client.upload(file: other, bucket: live.bucket, key: key, ifNoneMatch: true)
      } throws: { error in
        guard case S3Error.service(let status, _, _, _) = error else { return false }
        return status == 412
      }
      let head = try await base.head(bucket: live.bucket, key: key)
      #expect(head?.etag == written.etag, "the refused upload left the object as it was")
    }
  }
}
