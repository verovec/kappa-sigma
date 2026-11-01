import Foundation
import ImageKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0166: the scan reads its listing, headers and side files through one `FrameSource`;
/// `.files` is today's walk, and an in-memory source over the same tree gives the same inventory
/// (the seam the remote snapshot of 0167 plugs into).
@Suite("FrameSource — the scan's listing, headers and side files behind one seam")
struct FrameSourceTests {
  /// A source and a pixel reader answering from what `.files` read once: nothing touches disk.
  final class Recorded: Sendable {
    let listings: [String: InspectWalk.Listing]
    let headers: [String: FITSHeader]
    let contents: [String: Data]
    let planes: [String: PixelPlanes]
    let samples: [String: [Double]]

    init(roots: [String]) throws {
      var listings: [String: InspectWalk.Listing] = [:]
      var headers: [String: FITSHeader] = [:]
      var contents: [String: Data] = [:]
      var planes: [String: PixelPlanes] = [:]
      var samples: [String: [Double]] = [:]
      for root in roots {
        let listing = try FrameSource.files.listing(root, true)
        listings[root] = listing
        for path in listing.files {
          if InventoryBuilder.isFITS(path) {
            headers[path] = try FrameSource.files.header(path)
            planes[path] = try PixelReader.files.planes(path)
            samples[path] = try PixelReader.files.centerSample(path, 4096)
          } else {
            contents[path] = FrameSource.files.contents(path)
          }
        }
      }
      (self.listings, self.headers, self.contents) = (listings, headers, contents)
      (self.planes, self.samples) = (planes, samples)
    }

    var source: FrameSource {
      FrameSource(
        listing: { root, _ in
          guard let listing = self.listings[root] else { throw InspectError.unreadableFolder(root) }
          return listing
        },
        header: { path in
          guard let header = self.headers[path] else { throw InspectError.unreadableFolder(path) }
          return header
        },
        contents: { self.contents[$0] })
    }

    var pixels: PixelReader {
      PixelReader(
        planes: { path in
          guard let planes = self.planes[path] else { throw InspectError.unreadableFolder(path) }
          return planes
        },
        centerSample: { path, count in Array((self.samples[path] ?? []).prefix(count)) })
    }
  }

  @Test(
    "an in-memory source over a tree gives the inventory the files give", .scratchDirectory,
    arguments: ["golden-single-night", "golden-two-night"])
  func testScan_ThroughInjectedSource(name: String) throws {
    let oracle = try OracleFixtureTests.committedCase(name)
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let input = root.appendingPathComponent("in")
    try HeaderFixture.load(name).materialize(under: input)
    let fromFiles = try InventoryBuilder(timeZone: zone).scan(paths: [input.path])
    let recorded = try Recorded(roots: [input.path])
    // Nothing left on disk: the in-memory source alone answers.
    try FileManager.default.moveItem(at: input, to: root.appendingPathComponent("gone"))

    let fromMemory = try InventoryBuilder(
      timeZone: zone, pixels: recorded.pixels, source: recorded.source
    ).scan(paths: [input.path])

    #expect(fromMemory == fromFiles)
    #expect(!fromFiles.frames.isEmpty)
  }

  @Test(
    "the files source lists like the walk: packages skipped, output folders skipped",
    .scratchDirectory)
  func testFilesSourceEqualsWalk() throws {
    let dir = try InventoryBuilderFallbackTests.folder("walk")
    let light = InventoryBuilderTests.asi("'Light Frame'", filter: "'L'", exptime: "120.0")
    try TestFITS.write("lights/l_1.fits", in: dir, pixel: 900, cards: light)
    try TestFITS.write("lights/l_1.fits.txt.fits", in: dir, pixel: 900, cards: light)
    try TestFITS.write("output/stack.fits", in: dir, pixel: 900, cards: light)
    try TestFITS.write("old.astrostack/stacks/1/c.fits", in: dir, pixel: 900, cards: light)
    try Data("Gain=100".utf8).write(to: dir.appendingPathComponent("lights/l_1.fits.txt"))

    let listing = try FrameSource.files.listing(dir.path, true)
    let names = listing.files.map { InspectWalk.relative($0, to: dir.path) }

    #expect(names == ["lights/l_1.fits", "lights/l_1.fits.txt", "lights/l_1.fits.txt.fits"])
    #expect(listing.packages.map { InspectWalk.relative($0, to: dir.path) } == ["old.astrostack"])
    #expect(FrameSource.files.contents(dir.path + "/lights/l_1.fits.txt") == Data("Gain=100".utf8))
    #expect(FrameSource.files.contents(dir.path + "/none") == nil)
    #expect(try FrameSource.files.header(dir.path + "/lights/l_1.fits").string("IMAGETYP") != nil)
  }
}
