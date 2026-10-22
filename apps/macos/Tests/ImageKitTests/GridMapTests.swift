import Foundation
import ImageKit
import Testing

/// `GridMap` (card 0090): crops, flips and quarter turns as one whole-pixel map, and the header's
/// plate solution moved with the pixels — the same star keeps its RA/Dec.
@Suite("GridMap: whole-pixel moves and the WCS that follows them")
struct GridMapTests {
  /// One table row: a move built on a 5 × 3 grid, and where each corner lands.
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let build: @Sendable (GridMap) -> GridMap
    let size: SIMD2<Int>
    /// Output (x, y) of input (0, 0) and of input (4, 2), 0-based.
    let corners: [SIMD2<Int>]
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(name: "identity", build: { $0 }, size: [5, 3], corners: [[0, 0], [4, 2]]),
    Case(
      name: "crop 1 left, 1 first row", build: { $0.cropped(left: 1, first: 1, right: 0, last: 0) },
      size: [4, 2], corners: [[-1, -1], [3, 1]]),
    Case(name: "flip x", build: { $0.flippedX() }, size: [5, 3], corners: [[4, 0], [0, 2]]),
    Case(name: "flip y", build: { $0.flippedY() }, size: [5, 3], corners: [[0, 2], [4, 0]]),
    Case(
      name: "quarter turn", build: { $0.quarterTurned() }, size: [3, 5],
      corners: [[2, 0], [0, 4]]),
    Case(
      name: "two quarter turns = both flips", build: { $0.quarterTurned().quarterTurned() },
      size: [5, 3], corners: [[4, 2], [0, 0]]),
  ]

  @Test("each move sends the corners where expected and back", arguments: cases)
  func testMoves(_ row: Case) {
    let map = row.build(.identity(width: 5, height: 3))
    #expect(SIMD2(map.width, map.height) == row.size)
    for (input, expected) in zip([SIMD2(0, 0), SIMD2(4, 2)], row.corners) {
      #expect(map.output(ofInput: input) == expected)
      #expect(map.input(ofOutput: expected) == input)
    }
  }

  @Test("a TAN-SIP solution moved with the pixels gives every star the same RA/Dec")
  func testWCSFollows() throws {
    let header = WCSTests.header([
      ("CTYPE1", "'RA---TAN-SIP'"), ("CTYPE2", "'DEC--TAN-SIP'"), ("CRPIX1", "2.6"),
      ("CRPIX2", "1.7"), ("CRVAL1", "10.68"), ("CRVAL2", "41.27"), ("CD1_1", "-2.1E-4"),
      ("CD1_2", "3.0E-5"), ("CD2_1", "2.5E-5"), ("CD2_2", "2.0E-4"), ("A_ORDER", "2"),
      ("B_ORDER", "2"), ("A_2_0", "1.0E-3"), ("A_1_1", "-4.0E-4"), ("B_0_2", "2.0E-3"),
      ("B_1_1", "5.0E-4"), ("OBJECT", "'M31'"), ("CRPIX1A", "3.0"),
    ])
    let wcs = try #require(WCS(header: header))
    let base = GridMap.identity(width: 5, height: 3)
    let maps = [
      base.cropped(left: 1, first: 1, right: 1, last: 0), base.flippedX(), base.flippedY(),
      base.quarterTurned(),
      base.cropped(left: 0, first: 1, right: 2, last: 0).quarterTurned()
        .flippedX(),
    ]
    for map in maps {
      let moved = header.moved(by: map)
      #expect(moved.string("OBJECT") == "M31", "other cards stay")
      #expect(moved.string("CRPIX1A") == nil, "an alternate solution is not left unmoved")
      let solution = try #require(WCS(header: moved))
      for y in 0..<3 {
        for x in 0..<5 {
          let out = map.output(ofInput: SIMD2(x, y))
          guard (0..<map.width).contains(out.x), (0..<map.height).contains(out.y) else { continue }
          let before = wcs.sky(x: Double(x), y: Double(y))
          let after = solution.sky(x: Double(out.x), y: Double(out.y))
          #expect(TangentPlaneOracle.separation(before, after) < 1e-6, "\(map) at \(x),\(y)")
        }
      }
    }
  }

  @Test("a header without a TAN solution loses its WCS cards; dropping keeps the rest")
  func testDropping() {
    let header = WCSTests.header([
      ("CTYPE1", "'RA---ZEA'"), ("CRPIX1", "2"), ("CDELT1", "1E-4"), ("OBJECT", "'M31'"),
      ("PLTSOLVD", "T"), ("RADESYS", "'ICRS'"), ("PV1_1", "0.0"), ("CD3_3", "1.0"),
      ("WCSAXES", "2"), ("CDFORM", "'x'"), ("CTYPE1A", "'RA---TAN'"), ("CD1_1A", "1E-4"),
      ("WCSNAMEA", "'alt'"), ("FILTERA", "'L'"), ("WCSAXESA", "2"),
    ])
    let moved = header.moved(by: GridMap.identity(width: 5, height: 3).flippedX())
    #expect(moved.string("CRPIX1") == nil && moved.string("CTYPE1") == nil)
    #expect(moved.string("OBJECT") == "M31")
    #expect(header.droppingWCS().cards.map(\.keyword) == ["OBJECT", "CDFORM", "FILTERA"])
  }

  @Test("a quarter turn with unequal SIP orders declares the larger one on both axes")
  func testUnequalSIPOrders() throws {
    let header = WCSTests.header([
      ("CTYPE1", "'RA---TAN-SIP'"), ("CTYPE2", "'DEC--TAN-SIP'"), ("CRPIX1", "2.6"),
      ("CRPIX2", "1.7"), ("CRVAL1", "10.68"), ("CRVAL2", "41.27"), ("CD1_1", "-2.1E-4"),
      ("CD1_2", "3.0E-5"), ("CD2_1", "2.5E-5"), ("CD2_2", "2.0E-4"), ("A_ORDER", "2"),
      ("B_ORDER", "3"), ("A_2_0", "1.0E-3"), ("B_3_0", "2.0E-4"), ("B_1_2", "-1.0E-4"),
    ])
    let wcs = try #require(WCS(header: header))
    let map = GridMap.identity(width: 5, height: 3).quarterTurned()
    let moved = header.moved(by: map)
    #expect(moved.int("A_ORDER") == 3 && moved.int("B_ORDER") == 3)
    let solution = try #require(WCS(header: moved))
    for (x, y) in [(0, 0), (4, 2), (2, 1)] {
      let out = map.output(ofInput: SIMD2(x, y))
      let before = wcs.sky(x: Double(x), y: Double(y))
      let after = solution.sky(x: Double(out.x), y: Double(out.y))
      #expect(TangentPlaneOracle.separation(before, after) < 1e-6)
    }
  }
}
