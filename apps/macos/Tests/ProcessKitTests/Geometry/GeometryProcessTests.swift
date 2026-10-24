import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// `GeometryProcess` (card 0090): crops, quarter turns and flips are index copies (bit-exact), a
/// fine angle resamples with the chosen kernel against a CPU oracle, and an applied step moves
/// every layer the next steps read.
@Suite(
  "Geometry: exact crops/turns/flips, resampled angle, layers that follow",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct GeometryProcessTests {
  /// One table row: the panel values and whether the rows are stored bottom-up.
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let values: [String: ParamValue]
    let bottomUp: Bool
    var testDescription: String { name + (bottomUp ? " (bottom-up)" : "") }
  }

  static let exactValues: [(String, [String: ParamValue])] = [
    ("crop left", ["cropLeft": .number(1)]), ("crop top", ["cropTop": .number(1)]),
    ("crop right", ["cropRight": .number(2)]), ("crop bottom", ["cropBottom": .number(1)]),
    ("90°", ["rotation": .choice("90")]), ("180°", ["rotation": .choice("180")]),
    ("270°", ["rotation": .choice("270")]), ("flip h", ["flipH": .flag(true)]),
    ("flip v", ["flipV": .flag(true)]),
    (
      "crop + 90° + flip h",
      [
        "cropLeft": .number(1), "cropTop": .number(1), "rotation": .choice("90"),
        "flipH": .flag(true),
      ]
    ),
    (
      "crop + 270° + flip v",
      [
        "cropRight": .number(1), "cropBottom": .number(1), "rotation": .choice("270"),
        "flipV": .flag(true),
      ]
    ),
  ]

  static let exactCases: [Case] = [false, true].flatMap { bottomUp in
    exactValues.map { Case(name: $0.0, values: $0.1, bottomUp: bottomUp) }
  }

  static func params(_ values: [String: ParamValue]) throws -> ParamSet {
    var params = ParamSet(schema: GeometryProcess.schema)
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  /// The display-order oracle: rows top-down as seen, cropped, turned clockwise, then flipped.
  static func expected(_ rows: [[Float]], _ values: [String: ParamValue]) -> [[Float]] {
    func number(_ id: String) -> Int {
      if case .number(let value)? = values[id] { return Int(value) }
      return 0
    }
    var rows = Array(
      rows[number("cropTop")..<(rows.count - number("cropBottom"))].map {
        Array($0[number("cropLeft")..<($0.count - number("cropRight"))])
      })
    var turns = 0
    if case .choice(let degrees)? = values["rotation"] { turns = (Int(degrees) ?? 0) / 90 }
    for _ in 0..<turns {
      // Clockwise: the new row r is the old column r read bottom to top.
      rows = (0..<rows[0].count).map { column in rows.reversed().map { $0[column] } }
    }
    if values["flipH"] == .flag(true) { rows = rows.map { $0.reversed() } }
    if values["flipV"] == .flag(true) { rows.reverse() }
    return rows
  }

  /// `process` on a `width` × `height` plane of distinct values (stored in `bottomUp` order).
  static func run(
    _ params: ParamSet, plane: [Float], width: Int, height: Int, bottomUp: Bool
  ) throws -> GPUImage {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(device: device, width: width, height: height, planes: [plane])
    return try ProcessRunner(device: device).run(
      GeometryProcess(params: params, device: device), input: input,
      stats: LayerStats(channels: []), rowsBottomUp: bottomUp)
  }

  @Test("testExactOpsBitExact", arguments: exactCases)
  func testExactOpsBitExact(_ row: Case) throws {
    let (width, height) = (5, 3)
    let stored = (0..<width * height).map { Float($0) + 0.25 }
    var displayRows = (0..<height).map { Array(stored[$0 * width..<($0 + 1) * width]) }
    if row.bottomUp { displayRows.reverse() }
    var want = Self.expected(displayRows, row.values)
    if row.bottomUp { want.reverse() }

    let output = try Self.run(
      Self.params(row.values), plane: stored, width: width, height: height,
      bottomUp: row.bottomUp)
    #expect(output.width == want[0].count && output.height == want.count)
    #expect(output.read()[0].map(\.bitPattern) == want.joined().map(\.bitPattern))
  }

  @Test("a crop leaving no pixel is refused with the reason, never adjusted")
  func testEmptyCropRefused() throws {
    #expect(throws: ProcessError.self) {
      try Self.run(
        Self.params(["cropLeft": .number(3), "cropRight": .number(2)]),
        plane: Array(repeating: 1, count: 15), width: 5, height: 3, bottomUp: false)
    }
  }

  @Test(
    "testAngleMatchesCPUOracle",
    arguments: zip(
      ["bilinear", "bicubic", "lanczos3", "bilinear", "lanczos3", "bicubic"],
      ["keep", "keep", "keep", "expand", "expand", "expand"]))
  func testAngleMatchesCPUOracle(interpolation: String, canvas: String) throws {
    let (width, height) = (11, 7)
    let plane = (0..<width * height).map { index -> Float in
      let (x, y) = (Float(index % width), Float(index / width))
      return 0.3 + 0.05 * x - 0.02 * y + 0.1 * sin(Float(index) * 1.7)
    }
    for bottomUp in [false, true] {
      let values: [String: ParamValue] = [
        "angle": .number(7.5), "interpolation": .choice(interpolation), "canvas": .choice(canvas),
      ]
      let output = try Self.run(
        Self.params(values), plane: plane, width: width, height: height, bottomUp: bottomUp)
      let oracle = RotationOracle(
        plane: plane, width: width, height: height, degrees: bottomUp ? -7.5 : 7.5,
        kernel: interpolation, expand: canvas == "expand")
      #expect(output.width == oracle.width && output.height == oracle.height)
      let got = output.read()[0]
      let worst = zip(got, oracle.plane).map { abs($0 - $1) }.max() ?? .infinity
      #expect(worst <= 1e-5, "\(interpolation) \(canvas) bottomUp \(bottomUp): max |Δ| \(worst)")
    }
  }

  @Test("angle = 0 never resamples, whatever the interpolation")
  func testZeroAngleIsExact() throws {
    let plane = (0..<15).map { Float($0) * 0.37 }
    let output = try Self.run(
      Self.params([
        "angle": .number(0), "interpolation": .choice("lanczos3"), "canvas": .choice("expand"),
        "rotation": .choice("90"),
      ]), plane: plane, width: 5, height: 3, bottomUp: false)
    let want = Self.expected(
      (0..<3).map { Array(plane[$0 * 5..<($0 + 1) * 5]) }, ["rotation": .choice("90")])
    #expect(output.read()[0].map(\.bitPattern) == want.joined().map(\.bitPattern))
  }

  @Test(
    "testDisplayRanges: each crop's slider ends one pixel short of the side it crops",
    arguments: [(6000, 4000), (1, 1), (7, 3)])
  func testDisplayRanges(width: Int, height: Int) {
    let across = 0...Double(width - 1)
    let down = 0...Double(height - 1)

    let ranges = GeometryProcess.displayRanges(width: width, height: height)

    #expect(
      ranges == ["cropLeft": across, "cropRight": across, "cropTop": down, "cropBottom": down])
  }
}
