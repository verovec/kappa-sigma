import Foundation
import ImageKit
import TestSupport
import Testing

/// `downsampled` is the legacy `fits.File.ReadDownsampled` (trail detection reads frames through
/// it); `writeCrop` is `cropFITS` (the edge trim writes the colour-combine inputs with it).
@Suite("FITSFile — downsampled reads and rectangle crops")
struct DownsampleCropTests {
  static func file(_ data: Data, _ name: String = "x.fits") throws -> (FITSFile, URL) {
    let url = try ScratchDirectory.url.appendingPathComponent(name)
    try data.write(to: url)
    return (try FITSFile.read(at: url), url)
  }

  static let ramp: [Float] = (0..<20).map(Float.init)

  @Test("the smallest factor that fits, max or mean pooled per cell, ragged edges included", .scratchDirectory)
  func testDownsampled_pooling() throws {
    let (file, _) = try Self.file(FITSBytes.float32(width: 5, height: 4, planes: [Self.ramp]))
    let max = try file.downsampled(maxDimension: 3, pooling: .max)
    #expect(max.width == 3 && max.height == 2)
    #expect(max.grid == [6, 8, 9, 16, 18, 19])
    let mean = try file.downsampled(maxDimension: 3, pooling: .mean)
    #expect(mean.grid == [3, 5, 6.5, 13, 15, 16.5])
    let whole = try file.downsampled(maxDimension: 512, pooling: .max)
    #expect(whole.width == 5 && whole.height == 4 && whole.grid == Self.ramp.map(Double.init))
  }

  @Test("16-bit values are physical (BZERO applied) in double", .scratchDirectory)
  func testDownsampled_int16() throws {
    let (file, _) = try Self.file(FITSBytes.int16(width: 2, height: 1, raw: [-32768, 32767]))
    #expect(try file.downsampled(maxDimension: 1, pooling: .max).grid == [65535])
  }

  @Test("a crop keeps the rectangle's float32 values bit for bit, every plane", .scratchDirectory)
  func testWriteCrop_values() throws {
    let planes: [[Float]] = [Self.ramp, Self.ramp.map { $0 + 100 }, Self.ramp.map { -$0 }]
    let (file, _) = try Self.file(FITSBytes.float32(width: 5, height: 4, planes: planes))
    let out = try ScratchDirectory.url.appendingPathComponent("trim.fits")
    try file.writeCrop(to: out, x0: 1, y0: 1, x1: 4, y1: 3)
    let image = try FITSFile.read(at: out).image()
    #expect(image.width == 3 && image.height == 2)
    #expect(image.planes[0] == [6, 7, 8, 11, 12, 13])
    #expect(image.planes[1] == [106, 107, 108, 111, 112, 113])
    #expect(image.planes[2] == [-6, -7, -8, -11, -12, -13])
  }

  @Test("a 16-bit source crops to float32 physical values; an empty rectangle is an error", .scratchDirectory)
  func testWriteCrop_int16AndEmpty() throws {
    let (file, _) = try Self.file(FITSBytes.int16(width: 2, height: 2, raw: [-32768, 0, 1, 32767]))
    let out = try ScratchDirectory.url.appendingPathComponent("trim.fits")
    try file.writeCrop(to: out, x0: 1, y0: 0, x1: 9, y1: 2)
    let cropped = try FITSFile.read(at: out)
    #expect(cropped.header.int("BITPIX") == -32)
    #expect(try cropped.image().planes == [[32768, 65535]])
    #expect(throws: (any Error).self) { try file.writeCrop(to: out, x0: 2, y0: 0, x1: 2, y1: 2) }
  }
}
