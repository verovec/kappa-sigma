import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0167: a key space walks like a folder — byte order per folder, hidden and `output` folders
/// skipped, packages listed as skipped — and a remote path's scheme and bucket are no folder names.
@Suite("InspectWalk over keys — an S3 prefix listed like the disk")
struct RemoteListingTests {
  @Test("testSkipsLikeLocal: the same tree on disk and as keys lists the same", .scratchDirectory)
  func testSkipsLikeLocal() throws {
    let dir = try InventoryBuilderFallbackTests.folder("walk")
    let light = InventoryBuilderTests.asi("'Light Frame'", filter: "'L'", exptime: "120.0")
    for relative in [
      "lights/l_1.fits", "lights.fits", "lights/sub/l_2.fits", "output/stack.fits", "Output/s.fits",
      ".hidden/x.fits", "old.astrostack/stacks/1/c.fits", "Viewer.app/Contents/x.fits", ".dot.fits",
      "a-b/c.fits", "a/b.fits", "a.fits",
    ] {
      try TestFITS.write(relative, in: dir, pixel: 900, cards: light)
    }
    let local = try FrameSource.files.listing(under: dir.path, skippingOutput: true)
    let keys = try MemoryStore(tree: dir, prefix: "").objects.keys.sorted()

    let remote = InspectWalk.listing(keys: keys, under: "s3://astro/p", skippingOutput: true)

    let relative = { (paths: [String], root: String) in
      paths.map { InspectWalk.relative($0, to: root) }
    }
    #expect(relative(remote.files, "s3://astro/p") == relative(local.files, dir.path))
    #expect(relative(remote.packages, "s3://astro/p") == relative(local.packages, dir.path))
  }

  @Test("a folder marker key is no file")
  func testFolderMarkerIgnored() {
    let listing = InspectWalk.listing(
      keys: ["night/", "night/l.fits"], under: "s3://astro", skippingOutput: true)
    #expect(listing.files == ["s3://astro/night/l.fits"])
  }

  @Test(
    "testS3SchemeAndBucketNotTokens: a bucket named darks types nothing",
    arguments: [
      ("s3://darks/M31/lights/x.fits", FrameType.light), ("s3://darks/M31/x.fits", .unknown),
      ("s3://flats/x.fits", .unknown),
    ])
  func testS3SchemeAndBucketNotTokens(path: String, expected: FrameType) {
    #expect(PathMeta.typeFromFolders(path) == expected)
  }
}
