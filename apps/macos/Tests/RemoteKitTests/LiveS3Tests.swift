import CryptoKit
import Foundation
import RemoteKit
import TestSupport
import Testing

/// RemoteKit against a real S3 service: the local MinIO `just s3-live` starts, or the bucket `.env`
/// names (`LiveS3Environment`). Each test writes under a prefix of its own and removes it.
@Suite(
  "Live S3: a real round trip against an S3 service",
  .liveS3,
  .tags(.live), .serialized, .timeLimit(.minutes(5)))
struct LiveS3Tests {
  /// The configuration, its client, the bucket made sure of, and a prefix of this test alone.
  static func session() async throws -> (LiveS3Environment, S3Client, String) {
    let live = try #require(LiveS3Environment.current)
    let client = live.client()
    try await live.ensureBucket(client)
    try await live.sweep(client: client)
    return (live, client, LiveS3Environment.runPrefix())
  }

  @Test(
    "Upload 70 MiB (multipart) and 1 KiB, list, head, ranged get, download, delete",
    .scratchDirectory)
  func testRoundTrip() async throws {
    let (live, client, prefix) = try await Self.session()
    let scratch = try ScratchDirectory.url
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
      #expect(head?.etag == uploaded.etag, "an unchanged object keeps its ETag")
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

    try await live.removePrefix(prefix, client: client)
    #expect(try await client.list(bucket: live.bucket, prefix: prefix).isEmpty)
    #expect(try await client.head(bucket: live.bucket, key: prefix + "big.fit") == nil)
  }

  @Test("A listing past one page (1 001 keys) is whole, and one level of it too", .scratchDirectory)
  func testListingPagesPast1000Keys() async throws {
    let (live, client, prefix) = try await Self.session()
    let empty = try Self.file(try ScratchDirectory.url.appendingPathComponent("e"), bytes: 1)
    let keys = (0..<1001).map { String(format: "%@a/%04d.fit", prefix, $0) }
    do {
      try await Self.forEach(keys) { key in
        _ = try await client.upload(file: empty, bucket: live.bucket, key: key)
      }
      let listed = try await client.list(bucket: live.bucket, prefix: prefix)
      #expect(listed.map(\.key) == keys, "every page, in key order")
      let level = try await client.list(bucket: live.bucket, prefix: prefix, delimiter: "/")
      #expect(level.prefixes == [prefix + "a/"])
      #expect(level.objects.isEmpty)
    } catch {
      Issue.record(error)
    }
    try await live.removePrefix(prefix, client: client)
  }

  @Test(
    "A key with a space, a plus, an accent or nested folders round-trips as written",
    .scratchDirectory,
    // Not `a//b`: MinIO refuses an empty path segment (400 XMinioInvalidObjectName), AWS does not.
    arguments: ["with space.fit", "plus+sign.fit", "été/Hα.fit", "Nuit 2/Lights L/L_001.fit"])
  func testAwkwardKeysRoundTrip(_ name: String) async throws {
    let (live, client, prefix) = try await Self.session()
    let scratch = try ScratchDirectory.url
    let file = try Self.file(scratch.appendingPathComponent("f"), bytes: 4096)
    let key = prefix + name
    do {
      _ = try await client.upload(file: file, bucket: live.bucket, key: key)
      let listed = try await client.list(bucket: live.bucket, prefix: prefix)
      #expect(listed.map(\.key) == [key], "the listing names the key as written")
      let head = try await client.head(bucket: live.bucket, key: key)
      #expect(head?.size == 4096)
      let target = scratch.appendingPathComponent("down")
      _ = try await client.download(
        bucket: live.bucket, key: key, to: target, expect: head)
      #expect(try FileDigest.sha256Base64(target) == FileDigest.sha256Base64(file))
    } catch {
      Issue.record(error)
    }
    try await live.removePrefix(prefix, client: client)
  }

  /// Runs `body` over `items`, eight at a time.
  static func forEach(
    _ items: [String], _ body: @escaping @Sendable (String) async throws -> Void
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (index, item) in items.enumerated() {
        if index >= 8 { try await group.next() }
        group.addTask { try await body(item) }
      }
      try await group.waitForAll()
    }
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
