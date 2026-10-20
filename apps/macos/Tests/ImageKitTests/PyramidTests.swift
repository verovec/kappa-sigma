import Foundation
import ImageKit
import Testing

@Suite("Pyramid: block-averaged levels, never stride sampling")
struct PyramidTests {
  /// A deterministic uniform noise source (the same LCG as the legacy goldens).
  struct LCG {
    var state: UInt64
    mutating func next() -> Float {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Float(Double(state >> 11) / Double(1 << 53))
    }
  }

  static func standardDeviation(_ values: [Float]) -> Double {
    let mean = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
    let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
    return variance.squareRoot()
  }

  @Test("level 1 of a checkerboard is flat 0.5 (stride sampling would keep 0 or 1)")
  func testBlockAverageNotStride() {
    let size = 64
    let board = (0..<size * size).map { Float(($0 % size + $0 / size) % 2) }
    let pyramid = Pyramid(width: size, height: size, planes: [board], smallestSide: 8)
    let level1 = pyramid.levels[1]
    #expect(level1.width == 32 && level1.height == 32)
    #expect(level1.planes[0].allSatisfy { $0 == 0.5 })
  }

  @Test("a noise field's standard deviation halves per level (±10 %)")
  func testPyramid_noiseHalvesPerLevel() {
    let size = 512
    var lcg = LCG(state: 42)
    let noise = (0..<size * size).map { _ in lcg.next() }
    let pyramid = Pyramid(width: size, height: size, planes: [noise], smallestSide: 32)
    let deviations = pyramid.levels.map { Self.standardDeviation($0.planes[0]) }
    for (finer, coarser) in zip(deviations, deviations.dropFirst()) {
      #expect(abs(finer / coarser - 2) <= 0.2, "\(finer) → \(coarser)")
    }
  }

  @Test(
    "levels halve (rounding down) until the longer side fits the smallest side",
    arguments: [
      (6248, 4176, 512, [6248, 3124, 1562, 781, 390]),
      (513, 300, 512, [513, 256]),
      (512, 512, 512, [512]),
      (7, 5, 2, [7, 3, 1]),
    ])
  func testPyramid_levelSizes(width: Int, height: Int, smallest: Int, widths: [Int]) {
    let pyramid = Pyramid(
      width: width, height: height, planes: [[Float](repeating: 1, count: width * height)],
      smallestSide: smallest)
    #expect(pyramid.levels.map(\.width) == widths)
    #expect(pyramid.levels.last.map { max($0.width, $0.height) <= smallest } == true)
    #expect(pyramid.levels.allSatisfy { $0.planes[0].count == $0.width * $0.height })
  }

  @Test("a plane shorter than width × height is a caller bug: the process stops, nothing is read")
  func testPyramid_rejectsShortPlane() async {
    await #expect(processExitsWith: .failure) {
      _ = Pyramid(width: 64, height: 64, planes: [[Float](repeating: 0, count: 10)])
    }
  }

  @Test("every plane of a colour image gets its own levels")
  func testPyramid_planesStaySeparate() {
    let planes: [[Float]] = [
      [Float](repeating: 0.1, count: 16), [Float](repeating: 0.5, count: 16),
      [Float](repeating: 0.9, count: 16),
    ]
    let level1 = Pyramid(width: 4, height: 4, planes: planes, smallestSide: 2).levels[1]
    #expect(level1.planes.map(\.first) == [0.1, 0.5, 0.9])
  }

  @Test(
    "22 Mpx × 3 planes build in under 2 s on the dev host",
    .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "timing is local-only"))
  func testPerformance() async {
    let width = 6248
    let height = 3536
    let plane = [Float](repeating: 0.25, count: width * height)
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
      _ = await Pyramid.build(width: width, height: height, planes: [plane, plane, plane])
    }
    #expect(elapsed < .seconds(2), "\(elapsed)")
  }
}
