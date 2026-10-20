import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// `SaturationRepair` is the saturation half of `transient/satmask.go`: cases translated from
/// `satmask_test.go` (an 8×8 core on a 256×256 sky).
@Suite("SaturationRepair — clipped cores restored from the nights that still see them", .serialized)
struct SaturationRepairTests {
  static let size = 256
  static let core = (100..<108).flatMap { row in (200..<208).map { row * 256 + $0 } }

  /// Frame `index` with its core at `value` on a 0.1 sky.
  static func frames(_ values: [Float]) throws -> [URL] {
    try values.enumerated().map { index, value in
      var plane = [Float](repeating: 0.1 + Float(index) * 1e-4, count: size * size)
      for pixel in core { plane[pixel] = value }
      return try FloatFITS.write(
        try ScratchDirectory.url.appendingPathComponent("r_\(index).fits"), width: size, height: size, planes: [plane])
    }
  }

  static func corePixel(_ url: URL) throws -> Float {
    try FITSFile.read(at: url).image().planes[0][104 * size + 204]
  }

  @Test("most frames clipped: every plateau pixel repaired from the clean minority's median", .scratchDirectory)
  func testMajorityCore() throws {
    let urls = try Self.frames(Array(repeating: 0.99, count: 7) + Array(repeating: 0.55, count: 5))
    let counts = try SaturationRepair.repair(urls, ceilings: Array(repeating: 1, count: 12))
    #expect(counts.reduce(0, +) == 7 * 64)
    let cores = try urls.map(Self.corePixel)
    #expect(cores.prefix(7).allSatisfy { abs($0 - 0.55) <= 1e-4 } && cores.suffix(5).allSatisfy { $0 == 0.55 })
  }

  @Test(
    "do no harm: clipped everywhere, below the threshold, or under five clean frames",
    .scratchDirectory,
    arguments: [
      (Array(repeating: Float(0.99), count: 12), Float(0.99)),
      (Array(repeating: Float(0.85), count: 12), Float(0.85)),
      (Array(repeating: Float(0.99), count: 9) + Array(repeating: Float(0.55), count: 3), Float(0.99)),
    ])
  func testGuards(values: [Float], first: Float) throws {
    let urls = try Self.frames(values)
    let counts = try SaturationRepair.repair(urls, ceilings: Array(repeating: 1, count: values.count))
    let core = try Self.corePixel(urls[0])
    #expect(counts.reduce(0, +) == 0 && core == first)
  }

  @Test("each night is detected at its own ceiling", .scratchDirectory)
  func testPerGroupCeilings() throws {
    let urls = try Self.frames(Array(repeating: 0.99, count: 4) + Array(repeating: 0.495, count: 3) + Array(repeating: 0.30, count: 5))
    let ceilings: [Float] = Array(repeating: 1, count: 4) + Array(repeating: 0.5, count: 3) + Array(repeating: 1, count: 5)
    let counts = try SaturationRepair.repair(urls, ceilings: ceilings)
    #expect(counts.reduce(0, +) == 7 * 64)
    let cores = try urls.prefix(7).map(Self.corePixel)
    #expect(cores.allSatisfy { abs($0 - 0.30) <= 1e-4 })
  }

  @Test("no ceiling, no pass", .scratchDirectory)
  func testDisabled() throws {
    let urls = try Self.frames([0.99, 0.55])
    #expect(try SaturationRepair.repair(urls, ceilings: []) == [0, 0])
  }
}
