import Foundation
import ImageKit
import TestSupport
import Testing

/// `FITSFile.centerSample` is the legacy `fits.File.Stats` read: a contiguous run from the middle
/// of the whole data unit, physical values computed in double (no float32 rounding).
@Suite("FITSFile.centerSample reads the middle run of the data unit in double")
struct CenterSampleTests {
  static func file(_ data: Data) throws -> FITSFile {
    let url = try ScratchDirectory.url.appendingPathComponent("x.fits")
    try data.write(to: url)
    return try FITSFile.read(at: url)
  }

  @Test(
    "the run is centred; 0 or more than the image means every value",
    .scratchDirectory,
    arguments: [(4, 4), (5, 3), (0, 0), (99, 0)] as [(Int, Int)])
  func testCenterSample_int16(maxCount: Int, first: Int) throws {
    let file = try Self.file(FITSBytes.int16(width: 4, height: 3, raw: (0..<12).map(Int16.init)))
    let length = maxCount <= 0 || maxCount > 12 ? 12 : maxCount
    let expected: [Double] = (first..<first + length).map { 32768 + Double($0) }
    #expect(try file.centerSample(maxCount: maxCount) == expected)
  }

  @Test("the run crosses planes of a colour cube, in file order", .scratchDirectory)
  func testCenterSample_planes() throws {
    let planes: [[Float]] = [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11]]
    let file = try Self.file(FITSBytes.float32(width: 2, height: 2, planes: planes))
    #expect(try file.centerSample(maxCount: 6) == [3, 4, 5, 6, 7, 8])
  }

  @Test("BSCALE applies in double: 0.1 × 3 is not rounded to float32", .scratchDirectory)
  func testCenterSample_double() throws {
    let file = try Self.file(
      FITSBytes.int16(width: 1, height: 1, raw: [3], bzero: "0", bscale: "0.1"))
    #expect(try file.centerSample(maxCount: 1) == [0.1 * 3])
  }

  @Test("a truncated data unit is an error", .scratchDirectory)
  func testCenterSample_truncated() throws {
    let full = FITSBytes.int16(width: 64, height: 64, raw: [Int16](repeating: 1, count: 4096))
    let file = try Self.file(full.prefix(2880 + 100))
    #expect(throws: (any Error).self) { try file.centerSample(maxCount: 10) }
  }
}
