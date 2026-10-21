import Foundation
import Metal
import ProcessKit
import Testing

/// `HDRProcess`: the kernels against `HDROracle` (hdrcomp) on synthetic skies, cores and stars.
@Suite(
  "HDR: two-scale core compression, absolute thresholds, opening before the blur",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct HDRTests {
  /// One test image: planar planes, its size and the bundle statistics the process reads.
  struct Image {
    let width: Int
    let height: Int
    var planes: [[Float]]
    var stats: LayerStats

    /// Planes of `width`×`height` where `value(plane, x, y)` gives each pixel; the sky median of
    /// every plane is `sky`.
    init(width: Int, height: Int, planes: Int, sky: Double, value: (Int, Int, Int) -> Float) {
      self.width = width
      self.height = height
      self.planes = (0..<planes).map { plane in
        (0..<width * height).map { value(plane, $0 % width, $0 / width) }
      }
      stats = LayerStats(
        channels: Array(
          repeating: ChannelStats(median: sky, madn: 0.0002, minimum: 0, maximum: 1),
          count: planes))
    }
  }

  /// PO 2026-10-19: 0.00084 above the sky, softness 0.00118, σ 30 px, opening 16 px.
  static let validated: [String: ParamValue] = [
    "enabled": .flag(true), "kneeAboveSky": .number(0.00084), "softness": .number(0.00118),
    "sigma": .number(30), "openRadius": .number(16),
  ]

  /// A galaxy core (gaussian of σ `core` px, `peak` above the sky) on a sky with a ripple that
  /// does not depend on the sky level.
  static func galaxy(
    _ x: Int, _ y: Int, size: (width: Int, height: Int), sky: Double, peak: Double, core: Double
  ) -> Double {
    let (dx, dy) = (Double(x - size.width / 2), Double(y - size.height / 2))
    let ripple = 0.00013 * sin(Double(x) * 0.7) * cos(Double(y) * 0.45)
    return sky + ripple + peak * exp(-(dx * dx + dy * dy) / (2 * core * core))
  }

  static func run(
    _ image: Image, _ values: [String: ParamValue], scale: Double = 1
  ) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(
      device: device, width: image.width, height: image.height, planes: image.planes)
    let process = try HDRProcess(params: try params(values), device: device)
    return try ProcessRunner(device: device).run(
      process, input: input, stats: image.stats, scale: scale
    ).read()
  }

  static func params(_ values: [String: ParamValue]) throws -> ParamSet {
    var params = ParamSet(schema: HDRProcess.schema)
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  /// hdrcomp on `image` with the values of `values`, the sky = mean of the bundle medians.
  static func oracle(_ image: Image, _ values: [String: ParamValue]) throws -> [[Float]] {
    let params = try params(values)
    let sky = image.stats.channels.map(\.median).reduce(0, +) / Double(image.stats.channels.count)
    return HDROracle.render(
      image.planes, size: (image.width, image.height),
      t1: sky + params.number("kneeAboveSky"), softness: params.number("softness"),
      sigma: params.number("sigma"), openRadius: Int(params.number("openRadius").rounded()))
  }

  static func maxDifference(_ lhs: [[Float]], _ rhs: [[Float]]) -> Float {
    zip(lhs.joined(), rhs.joined()).map { abs($0 - $1) }.max() ?? .infinity
  }

  // MARK: Curve

  @Test("a 1-D ramp through t1 stays monotone with no slope break (C1), mono and colour")
  func testMonotoneC1() throws {
    for count in [1, 3] {
      let width = 512
      // From the sky to 0.02 above it: t1 sits a quarter of the way along the ramp. The planes
      // differ, so a swapped colour binding shows.
      let image = Image(width: width, height: 1, planes: count, sky: 0.0132) { plane, x, _ in
        Float((0.0132 + 0.02 * Double(x) / Double(width - 1)) * (1 - 0.1 * Double(plane)))
      }
      let values: [String: ParamValue] = [
        "enabled": .flag(true), "kneeAboveSky": .number(0.005), "softness": .number(0.002),
        "sigma": .number(4), "openRadius": .number(0),
      ]
      let out = try Self.run(image, values)
      #expect(Self.maxDifference(out, try Self.oracle(image, values)) <= 1.0 / 65535)
      // Away from the clamped edges the smooth part of a ramp is the ramp itself.
      for (plane, values) in out.enumerated() {
        let slopes = (8..<width - 9).map { Double(values[$0 + 1] - values[$0]) }
        #expect(slopes.allSatisfy { $0 > 0 }, "plane \(plane) of \(count): not monotone")
        let breaks = zip(slopes, slopes.dropFirst()).map { abs($1 - $0) / max($0, $1) }
        #expect((breaks.max() ?? 1) <= 0.05, "plane \(plane) of \(count): slope break")
      }
      // Compression happened: the top of the ramp is lower than the input.
      #expect(out[0][width - 9] < image.planes[0][width - 9] - 0.004)
    }
  }

  @Test("every channel of a pixel is scaled by one ratio: colour ratios kept to 1e-5")
  func testRatioSharedAcrossChannels() throws {
    let (width, height) = (160, 120)
    let gains: [Double] = [1.3, 1, 0.6]
    let image = Image(width: width, height: height, planes: 3, sky: 0.0132) { plane, x, y in
      Float(
        gains[plane]
          * Self.galaxy(
            x, y, size: (width, height), sky: 0.0132, peak: 0.08, core: 30))
    }
    let out = try Self.run(image, Self.validated)
    var worst = 0.0
    for index in 0..<width * height {
      let ratios = (0..<3).map { Double(out[$0][index]) / Double(image.planes[$0][index]) }
      worst = max(worst, (ratios.max() ?? 0) - (ratios.min() ?? 0))
    }
    #expect(worst <= 1e-5)
    #expect(Self.maxDifference(out, try Self.oracle(image, Self.validated)) <= 1.0 / 65535)
    // The core was compressed.
    let centre = height / 2 * width + width / 2
    #expect(out[1][centre] < image.planes[1][centre] - 0.01)
  }

  @Test("a dead pixel inside a compressed core goes to 0, never negative")
  func testDeadPixelInCoreStaysNonNegative() throws {
    let (width, height) = (160, 120)
    var image = Image(width: width, height: height, planes: 3, sky: 0.0132) { _, x, y in
      Float(Self.galaxy(x, y, size: (width, height), sky: 0.0132, peak: 0.08, core: 30))
    }
    let centre = height / 2 * width + width / 2
    for plane in 0..<3 { image.planes[plane][centre] = 1e-6 }
    let out = try Self.run(image, Self.validated)
    #expect(out.joined().allSatisfy { $0 >= 0 })
    #expect(out[1][centre] == 0)
    #expect(Self.maxDifference(out, try Self.oracle(image, Self.validated)) <= 1.0 / 65535)
  }

  // MARK: Stars

  @Test("opening before the blur: a bright star keeps its halo; without it the oracle rings")
  func testStarKeepsHalo() throws {
    let (width, height) = (96, 96)
    let image = Image(width: width, height: height, planes: 3, sky: 0.0132) { _, x, y in
      let (dx, dy) = (Double(x - 48), Double(y - 48))
      return Float(0.0132 + 0.9 * exp(-(dx * dx + dy * dy) / (2 * 3 * 3)))
    }
    let out = try Self.run(image, Self.validated)
    // The opened smooth part stays at the sky, under the knee: every pixel is left bit for bit.
    #expect(out.map { $0.map(\.bitPattern) } == image.planes.map { $0.map(\.bitPattern) })
    #expect(Self.maxDifference(out, try Self.oracle(image, Self.validated)) <= 1.0 / 65535)

    var unopened = Self.validated
    unopened["openRadius"] = .number(0)
    let ringed = try Self.oracle(image, unopened)
    let ring = zip(ringed.joined(), image.planes.joined()).map { Double($0 - $1) }.min() ?? 0
    #expect(ring < -1e-4, "without the opening the star should darken its surroundings")
    #expect(Self.maxDifference(try Self.run(image, unopened), ringed) <= 1.0 / 65535)
  }

  // MARK: Thresholds

  @Test(
    "thresholds are absolute above the bundle sky: pedestals 0.0336/0.0132/0.0068 compress alike")
  func testAbsoluteThresholds() throws {
    let (width, height) = (160, 120)
    for count in [1, 3] {
      var reductions: [[Double]] = []
      for pedestal in [0.0336, 0.0132, 0.0068] {
        let image = Image(width: width, height: height, planes: count, sky: pedestal) { _, x, y in
          Float(
            Self.galaxy(
              x, y, size: (width, height), sky: pedestal, peak: 0.05, core: 30))
        }
        let out = try Self.run(image, Self.validated)
        reductions.append(zip(image.planes[0], out[0]).map { Double($0 - $1) })
      }
      #expect((reductions[0].max() ?? 0) > 0.01, "the core must be compressed")
      for other in reductions.dropFirst() {
        let gap = zip(reductions[0], other).map { abs($0 - $1) }.max() ?? 1
        #expect(gap <= 2e-6, "\(count) plane(s): compression differs by \(gap) across pedestals")
      }
    }
  }

  @Test("the oracle agrees at the preview scale: σ and the radius are divided by it")
  func testPreviewScaleDividesPixels() throws {
    let (width, height) = (64, 48)
    let image = Image(width: width, height: height, planes: 3, sky: 0.0132) { plane, x, y in
      Float(
        Self.galaxy(x, y, size: (width, height), sky: 0.0132, peak: 0.07, core: 6)
          * (1 - 0.1 * Double(plane)))
    }
    let out = try Self.run(image, Self.validated, scale: 2)
    var halved = Self.validated
    halved["sigma"] = .number(15)
    halved["openRadius"] = .number(8)
    #expect(Self.maxDifference(out, try Self.oracle(image, halved)) <= 1.0 / 65535)
  }

  // MARK: Process

  @Test("off by default, and off returns the input bit for bit")
  func testDisabledIsIdentity() throws {
    let image = Image(width: 32, height: 8, planes: 3, sky: 0.0132) { plane, x, y in
      Float(0.0132 + 0.01 * Double(x * y + plane) / 300)
    }
    #expect(ParamSet(schema: HDRProcess.schema).flag("enabled") == false)
    let out = try Self.run(image, [:])
    #expect(out.map { $0.map(\.bitPattern) } == image.planes.map { $0.map(\.bitPattern) })
  }

  @Test("without the bundle statistics the sky is unknown: refused with the reason")
  func testNeedsBundleSky() throws {
    var image = Image(width: 8, height: 8, planes: 3, sky: 0.0132) { _, _, _ in 0.02 }
    image.stats = LayerStats(channels: [])
    #expect(throws: ProcessError.self) { try Self.run(image, Self.validated) }
  }

  @Test("HDR is a linear-stage process registered with the shipped ones, with .px σ and radius")
  func testRegistered() throws {
    #expect(try ProcessRegistry.standard().ids.contains(HDRProcess.id))
    #expect(HDRProcess.stage == .linear)
    #expect(HDRProcess.previewExactOnlyAt1to1)
    #expect(Set(HDRProcess.schema.pixelParameters) == ["sigma", "openRadius"])
  }

  @Test("HDR passes every process contract, mono and colour (σ and the radius scale)")
  func testContracts() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for count in [1, 3] {
      let image = Image(width: 40, height: 24, planes: count, sky: 0.0132) { plane, x, y in
        Float(
          Self.galaxy(x, y, size: (40, 24), sky: 0.0132, peak: 0.05, core: 5)
            * (1 - 0.1 * Double(plane)))
      }
      let input = try GPUImage(
        device: device, width: image.width, height: image.height, planes: image.planes)
      let contracts = try ProcessContracts(device: device, input: input, stats: image.stats)
      let violations = try contracts.violations(
        of: HDRProcess.self, params: try Self.params(Self.validated))
      #expect(violations.isEmpty, "\(count) plane(s): \(violations)")
    }
  }
}
