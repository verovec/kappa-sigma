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
  /// What the in-memory source was never given.
  struct Missing: Error {
    let path: String
  }

  /// What a scan read from disk — exactly the headers, side files, planes and samples it asked
  /// for, at the counts it asked — replayed by an in-memory source and pixel reader that answer
  /// nothing else.
  final class Recorder: Sendable {
    private struct Reads {
      var listings: [String: InspectWalk.Listing] = [:]
      var headers: [String: FITSHeader] = [:]
      var contents: [String: Data] = [:]
      var planes: [String: PixelPlanes] = [:]
      var samples: [String: [Double]] = [:]
    }
    private let reads = Mutex(Reads())

    /// `.files`, every answer kept.
    var recordingSource: FrameSource {
      FrameSource(
        walk: { root, skippingOutput in
          let listing = try FrameSource.files.listing(under: root, skippingOutput: skippingOutput)
          self.reads.withLock { $0.listings[root] = listing }
          return listing
        },
        header: { path in
          let header = try FrameSource.files.header(path)
          self.reads.withLock { $0.headers[path] = header }
          return header
        },
        contents: { path in
          let data = FrameSource.files.contents(path)
          self.reads.withLock { $0.contents[path] = data }
          return data
        })
    }

    /// `PixelReader.files`, every answer kept.
    var recordingPixels: PixelReader {
      PixelReader(
        planes: { path in
          let planes = try PixelReader.files.planes(path)
          self.reads.withLock { $0.planes[path] = planes }
          return planes
        },
        centerSample: { path, count in
          let sample = try PixelReader.files.centerSample(path, count)
          self.reads.withLock { $0.samples["\(count)|\(path)"] = sample }
          return sample
        })
    }

    /// The recorded answers, and `Missing` for anything the disk scan never asked.
    var source: FrameSource {
      FrameSource(
        walk: { root, _ in
          guard let listing = self.reads.withLock({ $0.listings[root] }) else {
            throw Missing(path: root)
          }
          return listing
        },
        header: { path in
          guard let header = self.reads.withLock({ $0.headers[path] }) else {
            throw Missing(path: path)
          }
          return header
        },
        contents: { path in self.reads.withLock { $0.contents[path] } })
    }

    /// The recorded pixels, and `Missing` for any other path or count.
    var pixels: PixelReader {
      PixelReader(
        planes: { path in
          guard let planes = self.reads.withLock({ $0.planes[path] }) else {
            throw Missing(path: path)
          }
          return planes
        },
        centerSample: { path, count in
          guard let sample = self.reads.withLock({ $0.samples["\(count)|\(path)"] }) else {
            throw Missing(path: path)
          }
          return sample
        })
    }
  }

  /// The inventory of `roots` from the files (plain, and recorded), then from memory once the
  /// files are gone.
  static func bothWays(_ roots: [URL], under base: URL, zone: TimeZone) throws
    -> (files: Inventory, memory: Inventory)
  {
    // Every root lies under `base` (by path components): moving it leaves nothing on disk.
    precondition(roots.allSatisfy { $0.pathComponents.starts(with: base.pathComponents) })
    let paths = roots.map(\.path)
    let plain = try InventoryBuilder(timeZone: zone).scan(paths: paths)
    let recorder = Recorder()
    let recorded = try InventoryBuilder(
      timeZone: zone, pixels: recorder.recordingPixels, source: recorder.recordingSource
    ).scan(paths: paths)
    precondition(recorded == plain, "recording changes nothing")
    try FileManager.default.moveItem(at: base, to: base.appendingPathExtension("gone"))
    let fromMemory = try InventoryBuilder(
      timeZone: zone, pixels: recorder.pixels, source: recorder.source
    ).scan(paths: paths)
    return (plain, fromMemory)
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
    // Nothing left on disk once recorded: the in-memory source alone answers.
    let (files, memory) = try Self.bothWays([input], under: input, zone: zone)

    #expect(memory == files)
    #expect(!files.frames.isEmpty)
  }

  @Test(
    "SharpCap sidecars, info.txt and pixel-typed frames come through the source, not the disk",
    .scratchDirectory)
  func testScan_SideFilesAndPixelsThroughSource() throws {
    let base = try InventoryBuilderFallbackTests.folder("captures")
    let capObj = base.appendingPathComponent("M33/CapObj")
    try FileManager.default.createDirectory(at: capObj, withIntermediateDirectories: true)
    try Data("L R G B Ha\nL L\n300 gain\n-15°\n".utf8).write(
      to: capObj.appendingPathComponent("info.txt"))
    for (index, slot) in [1, 2, 3, 4, 5].enumerated() {
      try InventoryBuilderWheelTests.slotFrame(
        "2021-08-14-0\(index)00_6-\(slot)-CapObj_0000.FIT",
        in: capObj.appendingPathComponent("2021-08-14_0\(index)_00_00Z"), slot: slot)
    }
    let session = base.appendingPathComponent("session")
    try TestFITS.write("a_flat.fits", in: session, pixel: 30000, cards: ["EXPTIME": "2.0"])
    try TestFITS.write("b_zero.fits", in: session, pixel: 300, cards: ["EXPTIME": "0.0"])
    let zone = TimeZone(identifier: "Europe/Paris") ?? .gmt

    let (files, memory) = try Self.bothWays([capObj, session], under: base, zone: zone)

    #expect(memory == files)
    #expect(files.frames.filter { $0.classSource == .wheel }.count == 5, "sidecars + info.txt read")
    #expect(files.frames.contains { $0.classSource == .heuristic }, "pixel curves read")
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

    let listing = try FrameSource.files.listing(under: dir.path, skippingOutput: true)
    let names = listing.files.map { InspectWalk.relative($0, to: dir.path) }

    #expect(names == ["lights/l_1.fits", "lights/l_1.fits.txt", "lights/l_1.fits.txt.fits"])
    #expect(listing.packages.map { InspectWalk.relative($0, to: dir.path) } == ["old.astrostack"])
    #expect(FrameSource.files.contents(dir.path + "/lights/l_1.fits.txt") == Data("Gain=100".utf8))
    #expect(FrameSource.files.contents(dir.path + "/none") == nil)
    #expect(try FrameSource.files.header(dir.path + "/lights/l_1.fits").string("IMAGETYP") != nil)
  }
}
