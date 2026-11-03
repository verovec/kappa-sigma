import Foundation
import ProjectKit
import TestSupport
import Testing

/// Card 0168: an S3 prefix is a source like a capture folder — its virtual path kept exactly as
/// the scan spells it, and the last scan it answered kept beside it.
@Suite("ProjectStore — remote sources and the scan they answered")
struct RemoteSourcesStoreTests {
  @Test(
    "testAddRemoteSource_KeepsVirtualPath: no file canonicalisation, one row per bucket + prefix",
    .scratchDirectory)
  func testAddRemoteSource_KeepsVirtualPath() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store

    let first = try store.addSource(remote: "conn-1", bucket: "astro", prefix: "nights/M31")
    let again = try store.addSource(remote: "conn-2", bucket: "astro", prefix: "nights/M31/")

    #expect(first.path == "s3://astro/nights/M31", "the scheme survives: no URL(fileURLWithPath:)")
    #expect(first.id == again.id, "UNIQUE (kind, path): one source per bucket and prefix")
    #expect(again.connectionID == "conn-1", "the connection it was read through is not re-pointed")
    #expect(again.bucket == "astro" && again.prefix == "nights/M31")
    #expect(first.readOnly && first.profileID == nil && first.kind == .remoteNight)
  }

  @Test(
    "a whole bucket is a source of its own, and a local night keeps its own row", .scratchDirectory)
  func testWholeBucketAndLocalNightCoexist() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store

    let whole = try store.addSource(remote: "conn-1", bucket: "astro", prefix: "/")
    let local = try store.addSource(kind: .night, path: "/captures/M31")

    #expect(whole.path == "s3://astro" && whole.prefix == "")
    #expect(local.kind == .night && local.bucket == nil && local.connectionID == nil)
    #expect(try store.sources().map(\.id) == [whole.id, local.id])
  }

  @Test("the last scan is kept by the source's path and replaced in place", .scratchDirectory)
  func testRemoteScanKeptPerSource() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store
    let remote = try store.addSource(remote: "conn-1", bucket: "astro", prefix: "nights/M31")
    let empty = Data(#"{"entries":{}}"#.utf8)
    let scanned = Data(#"{"entries":{"nights/M31/l.fits":{"etag":"e1","size":2880}}}"#.utf8)

    #expect(try store.remoteScan(of: remote.path) == nil, "never scanned: no cache")
    try store.setRemoteScan(empty, of: remote.path)
    try store.setRemoteScan(scanned, of: remote.path)

    #expect(try store.remoteScan(of: remote.path) == scanned, "the newer scan replaces the older")
    #expect(try store.remoteScan(of: "s3://astro/nights/M45") == nil, "kept per source")
  }

  @Test(
    "the trailing slash is not part of the spelling; anything else in the key is kept",
    arguments: [
      ("nights/M31", "s3://astro/nights/M31"), ("nights/M31/", "s3://astro/nights/M31"),
      ("nights/M31//", "s3://astro/nights/M31"), ("", "s3://astro"), ("/", "s3://astro"),
      // `a//b` and `/M31` are legal S3 keys: the scan must list what the user chose, not a
      // tidied-up guess (the 0169 review corrected 0168 here).
      ("/nights/M31", "s3://astro//nights/M31"), ("nights//M31", "s3://astro/nights//M31"),
    ])
  func testRemotePathSpelling(prefix: String, path: String) {
    #expect(ProjectSource.remotePath(bucket: "astro", prefix: prefix) == path)
  }

  @Test(
    "one prefix, however it is typed, is one row — and its profile reaches it", .scratchDirectory)
  func testRemoteSourceProfileAndSpelling() throws {
    let package = try ProjectStoreTests.newPackage()
    defer { try? package.close() }
    let store = package.store

    let typed = try store.addSource(remote: "conn-1", bucket: "astro", prefix: "nights/M31/")
    #expect(typed.path == "s3://astro/nights/M31" && typed.prefix == "nights/M31")
    let again = try store.addSource(remote: "conn-1", bucket: "astro", prefix: "nights/M31")
    #expect(again.id == typed.id)

    try store.setProfile("osc-dualband", kind: .remoteNight, path: typed.path)

    #expect(
      try store.sources().first { $0.id == typed.id }?.profileID == "osc-dualband",
      "a virtual path is not canonicalised: the UPDATE must find its row")
  }
}
