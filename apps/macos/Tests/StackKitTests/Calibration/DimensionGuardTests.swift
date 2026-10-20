import Foundation
import StackKit
import TestSupport
import Testing

/// Translated from `dims_test.go`: a master from another sensor never reaches Siril, and its
/// exclusion leaves the matcher's fallback intact.
@Suite("DimensionGuard — masters of another sensor are not candidates")
struct DimensionGuardTests {
  static func frame(_ name: String, _ width: Int, _ height: Int, in dir: URL) throws -> String {
    try TestFITS.write(name, in: dir, width: width, height: height, cards: [:]).path
  }

  @Test("same sensor keeps all; others are excluded and named, commonest size first", .scratchDirectory)
  func testDimensionGuard_keepMatching() throws {
    let dir = try ScratchDirectory.url
    let light = try Self.frame("light.fits", 64, 48, in: dir)
    let fitting = try Self.frame("master_fit.fits", 64, 48, in: dir)
    let foreign = try Self.frame("master_foreign.fits", 32, 24, in: dir)
    let other = try Self.frame("master_other.fits", 100, 100, in: dir)
    let missing = dir.appendingPathComponent("nowhere.fits").path
    let pool = { (paths: [String]) in paths.map { CalibrationMaster(type: .flat, path: $0) } }

    let same = DimensionGuard.keepMatching(pool([fitting, fitting]), lightPath: light)
    #expect(same.masters.map(\.path) == [fitting, fitting])
    #expect(same.note == nil)
    let one = DimensionGuard.keepMatching(pool([fitting, foreign]), lightPath: light)
    #expect(one.masters.map(\.path) == [fitting])
    #expect(one.note == "1 calibration master(s) from another sensor (32×24) were not considered — these lights are 64×48")
    let grouped = DimensionGuard.keepMatching(pool([foreign, other, foreign]), lightPath: light)
    #expect(grouped.masters.isEmpty)
    #expect(
      grouped.note
        == "3 calibration master(s) from another sensor (32×24 (×2), 100×100) were not considered — these lights are 64×48")
    #expect(DimensionGuard.keepMatching(pool(["", missing]), lightPath: light).masters.map(\.path) == ["", missing])
    let raw = dir.appendingPathComponent("raw.dng").path
    #expect(DimensionGuard.keepMatching(pool([foreign, other]), lightPath: raw).masters.map(\.path) == [foreign, other])
  }

  @Test("excluding a foreign RGB flat lets the capture's own flat be found (ASI2600MC)", .scratchDirectory)
  func testDimensionGuard_fallbackIntact() throws {
    let dir = try ScratchDirectory.url
    let light = try Self.frame("light.fits", 624, 417, in: dir)
    let own = try Self.frame("own_flat.fits", 624, 417, in: dir)
    let foreign = try Self.frame("foreign_flat.fits", 606, 404, in: dir)
    let pool = [
      CalibrationFixtures.master(.flat, path: foreign, filter: "RGB", frames: 30, fromLibrary: true),
      CalibrationFixtures.master(.flat, path: own, frames: 50),
    ]
    let key = SetKey(type: .light, filter: "RGB", color: true)
    #expect(CalibrationMatcher.match(LightRef(key: key), masters: pool).flat?.path == foreign)
    let usable = DimensionGuard.keepMatching(pool, lightPath: light)
    #expect(CalibrationMatcher.match(LightRef(key: key), masters: usable.masters).flat?.path == own)
    #expect(usable.note?.contains("606×404") == true)
  }

  @Test("same dimensions: equal, transposed differs, unreadable is unknown", .scratchDirectory)
  func testDimensionGuard_sameDimensions() throws {
    let dir = try ScratchDirectory.url
    let a = try Self.frame("a.fits", 64, 48, in: dir)
    let b = try Self.frame("b.fits", 64, 48, in: dir)
    let c = try Self.frame("c.fits", 48, 64, in: dir)
    let absent = dir.appendingPathComponent("absent.fits").path
    #expect(DimensionGuard.sameDimensions(a, b) == true)
    #expect(DimensionGuard.sameDimensions(a, c) == false)
    #expect(DimensionGuard.sameDimensions(absent, b) == nil)
    #expect(DimensionGuard.sameDimensions(a, absent) == nil)
    #expect(DimensionGuard.sameDimensions("", b) == nil)
  }
}
