import Foundation
import StackKit
import Testing

/// `MasterStats` and `MasterWarning`: what a master's pixels say, and the documented thresholds
/// a suspicious one crosses (the M 45 corrupted flats, a warm dark) — warnings only, never acted
/// on (R2).
@Suite("MasterStats — a calibration master's statistics and its warnings")
struct MasterInspectTests {
  static let size = 200

  /// A normalised flat: `centre` in the middle, `corner` at the corners, linear in the radius.
  static func flat(centre: Float, corner: Float) -> [Float] {
    let half = Float(size - 1) / 2
    let reach = (half * half * 2).squareRoot()
    return (0..<size * size).map { index in
      let dx = Float(index % size) - half
      let dy = Float(index / size) - half
      let radius = (dx * dx + dy * dy).squareRoot() / reach
      return centre + (corner - centre) * radius
    }
  }

  /// A dark at `level` with `hot` pixels at full scale, spread over the frame.
  static func dark(level: Float, hot: Int) -> [Float] {
    var plane = (0..<size * size).map { level + Float($0 % 7) * 0.0001 }
    for index in 0..<hot { plane[(index * 7919) % plane.count] = 1 }
    return plane
  }

  static func patchMedian(_ plane: [Float], width: Int, x0: Int, y0: Int, side: Int) -> Float {
    var values: [Float] = []
    for y in y0..<y0 + side { for x in x0..<x0 + side { values.append(plane[y * width + x]) } }
    return values.sorted()[values.count / 2]
  }

  /// The corner/centre ratio straight from the definition: 10 % patches of the 2×2 block means.
  static func directVignetting(_ raw: [Float]) -> Double {
    let width = size / 2
    let plane = (0..<width * width).map { index -> Float in
      let (x, y) = (2 * (index % width), 2 * (index / width))
      let block = [raw[y * size + x], raw[y * size + x + 1], raw[(y + 1) * size + x]]
      return (block.reduce(0, +) + raw[(y + 1) * size + x + 1]) / 4
    }
    let side = width / 10
    let far = width - side
    let corners = [(0, 0), (far, 0), (0, far), (far, far)].map {
      patchMedian(plane, width: width, x0: $0.0, y0: $0.1, side: side)
    }
    let centre = patchMedian(
      plane, width: width, x0: (width - side) / 2, y0: (width - side) / 2, side: side)
    return (Double(corners.reduce(0, +)) / 4 / Double(centre) - 1) * 100
  }

  @Test("a clean flat: every stat present, darker corners, no warning")
  func testStats() throws {
    let plane = Self.flat(centre: 0.30, corner: 0.22)
    let stats = MasterStats(type: .flat, width: Self.size, height: Self.size, planes: [plane])
    #expect(stats.median > 0.22 && stats.median < 0.30)
    #expect(stats.madn > 0)
    #expect(stats.min == plane.min().map(Double.init))
    #expect(stats.max == plane.max().map(Double.init))
    #expect(stats.quadrantMedians.count == 4)
    #expect(stats.quadrantMedians.allSatisfy { abs($0 - stats.quadrantMedians[0]) < 1e-6 })
    let vignetting = try #require(stats.vignettingPct)
    #expect(abs(vignetting - Self.directVignetting(plane)) < 1e-6)
    #expect(vignetting < 0)
    #expect(stats.clippedPct == 0)
    #expect(stats.hotPixels == nil, "hot pixels are a dark's statistic")
    #expect(MasterWarning.all(for: stats).isEmpty)
  }

  @Test(
    "suspicious masters cross their documented threshold, with the measured value",
    arguments: [
      (
        MasterStats(
          type: .flat, width: size, height: size, planes: [flat(centre: 0.055, corner: 0.058)]),
        [MasterWarning.Kind.cornersBrighter, .underExposed]
      ),
      (
        MasterStats(
          type: .flat, width: size, height: size, planes: [flat(centre: 1.2, corner: 0.8)]),
        [.clipped]
      ),
      (
        MasterStats(type: .dark, width: size, height: size, planes: [dark(level: 0.008, hot: 400)]),
        [.clipped, .hotPixels]
      ),
      (
        MasterStats(type: .dark, width: size, height: size, planes: [dark(level: 0.008, hot: 10)]),
        []
      ),
    ])
  func testWarnings(stats: MasterStats, kinds: [MasterWarning.Kind]) {
    let warnings = MasterWarning.all(for: stats)
    #expect(warnings.map(\.kind) == kinds)
    #expect(warnings.allSatisfy { !$0.message.isEmpty && $0.message.contains("threshold") })
  }

  @Test("hot pixels and clipped % are counted exactly, not sampled")
  func testDarkCounts() throws {
    let plane = Self.dark(level: 0.008, hot: 400)
    let stats = MasterStats(type: .dark, width: Self.size, height: Self.size, planes: [plane])
    #expect(stats.hotPixels == 400)
    #expect(abs(stats.clippedPct - 400.0 / Double(plane.count) * 100) < 1e-9)
    #expect(stats.vignettingPct == nil, "vignetting is a flat's statistic")
  }

  @Test("an RGB master is measured on the mean of its planes")
  func testColourPlanes() {
    let red = [Float](repeating: 0.2, count: Self.size * Self.size)
    let blue = [Float](repeating: 0.4, count: Self.size * Self.size)
    let stats = MasterStats(type: .bias, width: Self.size, height: Self.size, planes: [red, blue])
    #expect(abs(stats.median - 0.3) < 1e-6)
    #expect(stats.madn == 0)
  }

  @Test(
    "a sampled CFA flat is measured over every Bayer phase: uniform reads uniform",
    arguments: [100, 400, 1600])
  func testSampledBayerFlat(budget: Int) throws {
    // RGGB at 0.4 / 0.1 / 0.1 / 0.25, no vignetting at all; 210 px puts the far patches (21 px)
    // at odd offsets, as on a real 6248 px master.
    let side = 210
    let plane = (0..<side * side).map { index -> Float in
      let (x, y) = (index % side, index / side)
      return [[0.4, 0.1], [0.1, 0.25]][y % 2][x % 2]
    }
    let stats = MasterStats(
      type: .flat, width: side, height: side, planes: [plane], sampleBudget: budget)
    let vignetting = try #require(stats.vignettingPct)
    #expect(abs(vignetting) < 1, "phase aliasing reads a flat field as vignetted: \(vignetting) %")
  }

  @Test("a quantised dark with MAD 0 counts no hot pixels one step above its median")
  func testQuantisedDarkHasFloor() {
    var plane = [Float](repeating: 500, count: Self.size * Self.size)
    for index in stride(from: 0, to: plane.count, by: 3) { plane[index] = 501 }
    let stats = MasterStats(type: .dark, width: Self.size, height: Self.size, planes: [plane])
    #expect(stats.madn == 0)
    #expect(stats.hotPixels == 0)
  }

  @Test("an image without pixels, or whose plane is not width × height, measures as empty")
  func testMalformedPlanes() {
    for planes in [[[Float]](), [[Float](repeating: 0.5, count: 10)]] {
      let stats = MasterStats(type: .flat, width: Self.size, height: Self.size, planes: planes)
      #expect(stats.pixelCount == 0)
      #expect(stats.vignettingPct == nil)
      #expect(MasterWarning.all(for: stats).isEmpty)
    }
  }
}
