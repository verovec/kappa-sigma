import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0192: the frames a project downloaded from buckets are removed only as that project's own
/// folder under the scratch folder — a predicate decided on paths alone, and a deletion that
/// takes nothing the predicate did not allow.
@Suite("RemoteFrameCache — only a project's own copies are ever removed")
struct RemoteFrameCacheRemovalTests {
  static let scratch = URL(fileURLWithPath: "/Volumes/Scratch/AstroStack/Work")

  /// A cache root and what must never be deleted, against the scratch folder above.
  struct Case: Sendable, CustomTestStringConvertible {
    let root: String
    var protected: [String] = []
    let removable: Bool
    let why: String
    var testDescription: String { "\(why): \(root)" }
  }

  static let cases: [Case] = [
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d", removable: true,
      why: "a project's folder of copies"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames", removable: false,
      why: "every project's copies at once"),
    Case(root: "/Volumes/Scratch/AstroStack/Work", removable: false, why: "the scratch folder"),
    Case(root: "/", removable: false, why: "the root of the disk"),
    Case(root: "/Volumes/Scratch", removable: false, why: "a volume"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d/astro", removable: false,
      why: "a folder inside a project's copies"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/../../../Captures", removable: false,
      why: "a path that climbs out"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/..", removable: false,
      why: "the scratch folder, spelled as a child"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/run_20261111/light_L", removable: false,
      why: "a run's work folder"),
    Case(root: "/Users/po/Documents/astro/captures/M31", removable: false, why: "a capture night"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d",
      protected: ["/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d/night"],
      removable: false, why: "a folder a capture night lives in"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d",
      protected: ["/Volumes/Scratch/AstroStack"], removable: false,
      why: "a folder inside the library or a capture"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d",
      protected: ["/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d"],
      removable: false, why: "a folder that is itself a source"),
    Case(
      root: "/Volumes/Scratch/AstroStack/Work/remote-frames/M31-0a1b2c3d",
      protected: ["/Users/po/AstroStack/Projects/M31.astrostack", "/Users/po/astro/library"],
      removable: true, why: "a project's copies, its package and library elsewhere"),
  ]

  @Test("testRemovable: decided on the paths, nothing touched", arguments: cases)
  func testRemovable(example: Case) {
    let cache = RemoteFrameCache(root: URL(fileURLWithPath: example.root))
    let protected = example.protected.map { URL(fileURLWithPath: $0) }
    #expect(
      cache.isRemovable(scratch: Self.scratch, protected: protected) == example.removable,
      "\(example.why)")
  }

  /// A frame kept in `cache` as a run leaves it.
  static func keep(_ name: String, in cache: RemoteFrameCache) throws {
    let file = cache.file(bucket: "astro", key: "M31/" + name)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("frame \(name)".utf8).write(to: file)
    try cache.keep(file, as: "9|e")
  }

  @Test(
    "testRemove_DeletesOnlyTheProjectsCache: its neighbours, a capture and a run stay",
    .scratchDirectory)
  func testRemove_DeletesOnlyTheProjectsCache() throws {
    let base = try ScratchDirectory.url
    let scratch = base.appendingPathComponent("Work")
    let home = scratch.appendingPathComponent(RemoteFrameCache.folderName)
    let mine = RemoteFrameCache(root: home.appendingPathComponent("M31-0a1b2c3d"))
    let other = RemoteFrameCache(root: home.appendingPathComponent("M42-ffffffff"))
    try Self.keep("l_1.fits", in: mine)
    try Self.keep("l_2.fits", in: mine)
    try Self.keep("l_1.fits", in: other)
    let capture = base.appendingPathComponent("captures/M31/l_1.fits")
    let run = scratch.appendingPathComponent("run_1/light_L/00001_l_1.fits")
    for file in [capture, run] {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("mine".utf8).write(to: file)
    }

    let freed = try mine.remove(scratch: scratch, protected: [capture.deletingLastPathComponent()])

    let files = FileManager.default
    #expect(freed > 0 && !files.fileExists(atPath: mine.root.path))
    #expect(mine.size() == 0 && mine.kept(among: ["s3://astro/M31/l_1.fits"]).isEmpty)
    #expect(other.size() > 0, "another project's copies are not this one's")
    #expect(files.fileExists(atPath: capture.path) && files.fileExists(atPath: run.path))
    #expect(files.fileExists(atPath: home.path), "the folder of every project's copies stays")
  }

  @Test(
    "a folder the predicate refuses is not deleted, and the refusal names it",
    .scratchDirectory)
  func testRemove_Refused_DeletesNothing() throws {
    let base = try ScratchDirectory.url
    let scratch = base.appendingPathComponent("Work")
    let capture = base.appendingPathComponent("captures/M31")
    try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
    try Data("light".utf8).write(to: capture.appendingPathComponent("l_1.fits"))
    // A cache pointed at a capture night by mistake: the worst a wrong root can be.
    let wrong = RemoteFrameCache(root: capture)

    #expect(throws: RemoteFrameCache.NotRemovable(path: capture.path)) {
      _ = try wrong.remove(scratch: scratch, protected: [])
    }
    #expect(FileManager.default.fileExists(atPath: capture.appendingPathComponent("l_1.fits").path))
  }

  @Test("nothing kept: nothing to remove, nothing freed", .scratchDirectory)
  func testRemove_NothingKept() throws {
    let scratch = try ScratchDirectory.url.appendingPathComponent("Work")
    let cache = RemoteFrameCache(
      root: scratch.appendingPathComponent(RemoteFrameCache.folderName + "/M31-0a1b2c3d"))
    #expect(try cache.remove(scratch: scratch, protected: []) == 0)
  }
}
