import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Card 0047: the library folder is the truth; its index in the project database follows it.
@Suite("CalibrationLibrary — index the master folder into project.db")
struct CalibrationLibraryTests {
  static func master(_ name: String, in dir: URL, size: (Int, Int) = (16, 12), sig: String?) throws
  {
    try TestFITS.write("\(name).fits", in: dir, width: size.0, height: size.1, cards: [:])
    if let sig { try Data(sig.utf8).write(to: dir.appendingPathComponent("\(name).sig")) }
  }

  static func package(in dir: URL) throws -> ProjectPackage {
    try ProjectPackage.create(at: dir.appendingPathComponent("M31.astrostack"))
  }

  @Test(
    "a library folder indexes fully; a changed .sig updates its row; a removed file deletes it",
    .scratchDirectory)
  func testReindexFromFolder() throws {
    let root = try ScratchDirectory.url
    let library = root.appendingPathComponent("library")
    try Self.master("master_BIAS_g0o50_b1", in: library, sig: "aaa\n10")
    try Self.master(
      "master_DARK_300000ms_g100o50_b1_-17C", in: library, size: (32, 24), sig: "bbb\n2")
    try Self.master("master_FLAT_15000ms_g100o50_b1_0C_n2026-09-22", in: library, sig: nil)
    try Data("ignored".utf8).write(
      to: library.appendingPathComponent("master_DARK_300000ms_g100o50_b1_-17C_defects.lst"))
    try FileManager.default.createDirectory(
      at: library.appendingPathComponent("catalogues"), withIntermediateDirectories: true)
    // A half-written master the legacy engine left behind is never a candidate.
    try Self.master(
      ".tmp_run_20260907_100642_master_DARK_60000ms_g0o50_b1_-11C", in: library, sig: nil)
    let package = try Self.package(in: root)
    defer { try? package.close() }
    let index = CalibrationLibrary(folder: library)

    #expect(
      try index.reindex(into: package.store)
        == CalibrationSyncReport(inserted: 3, updated: 0, deleted: 0))
    let masters = try CalibrationLibrary.masters(in: package.store)
    #expect(masters.map(\.type) == [.bias, .dark, .flat])
    #expect(masters.allSatisfy { $0.fromLibrary })
    let dark = try #require(masters.first { $0.type == .dark })
    #expect(dark.exposureMs == 300_000)
    #expect(dark.gain == 100)
    #expect(dark.offset == 50)
    #expect(dark.tempMilliC == -17000)
    #expect(dark.frameCount == 2)
    #expect(masters.first { $0.type == .flat }?.session == "2026-09-22")
    #expect(
      try package.store.calibrationMasters().first { $0.type == "DARK" }.map {
        [$0.width, $0.height]
      } == [32, 24])

    try Data("ccc\n12".utf8).write(
      to: library.appendingPathComponent("master_DARK_300000ms_g100o50_b1_-17C.sig"))
    try FileManager.default.removeItem(
      at: library.appendingPathComponent("master_BIAS_g0o50_b1.fits"))
    #expect(
      try index.reindex(into: package.store)
        == CalibrationSyncReport(inserted: 0, updated: 1, deleted: 1))
    #expect(
      try CalibrationLibrary.masters(in: package.store).first { $0.type == .dark }?.frameCount == 12
    )
    #expect(
      try index.reindex(into: package.store)
        == CalibrationSyncReport(inserted: 0, updated: 0, deleted: 0))
  }

  @Test("a missing library folder is an error naming it", .scratchDirectory)
  func testCalibrationLibrary_missingFolder() throws {
    let missing = try ScratchDirectory.url.appendingPathComponent("nope")
    #expect(throws: CalibrationError.unreadableLibrary(missing.path)) {
      try CalibrationLibrary(folder: missing).scan()
    }
  }
}

/// The real library under `~/Documents/astro/library` (live only).
@Suite("Live calibration library", .liveFixtures, .tags(.live), .timeLimit(.minutes(1)))
struct LiveCalibrationLibraryTests {
  @Test("the real library indexes every master it holds")
  func testCalibrationLibrary_liveLibrary() throws {
    let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
      "Documents/astro/library")
    guard FileManager.default.fileExists(atPath: folder.path) else {
      try Test.cancel("no ~/Documents/astro/library")
    }
    let rows = try CalibrationLibrary(folder: folder).scan()
    let fits = try FileManager.default.contentsOfDirectory(atPath: folder.path)
      .filter { $0.hasSuffix(".fits") && !$0.hasPrefix(".") }
    #expect(rows.count == fits.count)
    #expect(rows.allSatisfy { $0.width > 0 && $0.height > 0 })
  }
}
