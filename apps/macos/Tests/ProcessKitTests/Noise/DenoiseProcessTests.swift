import Metal
import ProcessKit
import Testing

@Suite(
  "Denoise: starlet soft-thresholds per scale, luminance and colour amounts, star protection",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct DenoiseProcessTests {
  static let width = 48
  static let height = 40

  /// A gradient sky with Gaussian noise per channel, and one star.
  static func field(channels: Int = 3) -> [[Float]] {
    (0..<channels).map { channel in
      let noise = DenoiseOracle.noise(
        count: width * height, sigma: 0.01, seed: UInt64(17 + channel))
      return (0..<(width * height)).map { index in
        let (x, y) = (index % width, index / width)
        let dx = Double(x - 30)
        let dy = Double(y - 12)
        let star = 0.6 * exp(-(dx * dx + dy * dy) / 4)
        return Float(0.1 + 0.002 * Double(x) + 0.03 * Double(channel) + star) + noise[index]
      }
    }
  }

  static let stats = LayerStats(
    channels: (0..<3).map {
      ChannelStats(median: 0.15 + 0.03 * Double($0), madn: 0.01, minimum: 0, maximum: 1)
    })

  static func params(_ values: DenoiseOracle.Values) throws -> ParamSet {
    var params = ParamSet(schema: DenoiseProcess.schema)
    for (scale, strength) in values.strengths.enumerated() {
      try params.set("scale\(scale + 1)", .number(strength))
    }
    try params.set("amount", .number(values.amount))
    try params.set("noise", .number(values.noise))
    try params.set("luminance", .number(values.luminance))
    try params.set("chrominance", .number(values.chrominance))
    try params.set("protectStars", .flag(values.protectStars))
    return params
  }

  static func render(
    _ planes: [[Float]], values: DenoiseOracle.Values, stats: LayerStats = stats
  ) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(device: device, width: width, height: height, planes: planes)
    return try ProcessRunner(device: device).run(
      DenoiseProcess(params: params(values), device: device), input: input, stats: stats
    ).read()
  }

  @Test("amount 0 returns the input bit for bit, whatever the other values")
  func testApply_AmountZero_IsIdentity() throws {
    let planes = Self.field()
    var values = DenoiseOracle.Values(strengths: [5, 5, 5, 5], amount: 0)
    values.protectStars = true
    values.chrominance = 0.3
    #expect(try Self.render(planes, values: values) == planes)
    #expect(DenoiseProcess.schema.specs.first { $0.id == "amount" }?.defaultValue == .number(0))
  }

  @Test(
    "the kernel equals the CPU starlet oracle (mean |Δ| ≤ 1e-5, max |Δ| ≤ 1e-4)",
    arguments: [
      DenoiseOracle.Values(),
      DenoiseOracle.Values(strengths: [1, 0, 0, 0]),
      DenoiseOracle.Values(strengths: [0, 0, 0, 2]),
      DenoiseOracle.Values(strengths: [5, 5, 5, 5], protectStars: true),
      DenoiseOracle.Values(amount: 0.7, luminance: 1, chrominance: 0.4),
      DenoiseOracle.Values(amount: 1, luminance: 0, chrominance: 1, protectStars: true),
    ])
  func testKernel_MatchesCPUOracle(values: DenoiseOracle.Values) throws {
    for channels in [1, 3] {
      let planes = Self.field(channels: channels)
      let out = try Self.render(planes, values: values)
      let expected = DenoiseOracle.denoise(
        planes, width: Self.width, height: Self.height, stats: Self.stats, values: values)
      let deltas = zip(out.joined(), expected.joined()).map { abs(Double($0) - Double($1)) }
      let mean = deltas.reduce(0, +) / Double(deltas.count)
      #expect(mean <= 1e-5, "\(channels) planes")
      #expect(deltas.max() ?? 0 <= 1e-4, "\(channels) planes")
    }
  }

  @Test("on a flat noisy field the MAD falls with the amount; a star keeps its peak if protected")
  func testNoiseDrops_FlatField() throws {
    let count = Self.width * Self.height
    let flat = [DenoiseOracle.noise(count: count, sigma: 0.01, seed: 3).map { 0.1 + $0 }]
    let stats = LayerStats(channels: [
      ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1)
    ])
    let mads = try [0.0, 0.5, 1.0].map { amount in
      DenoiseOracle.mad(
        try Self.render(flat, values: DenoiseOracle.Values(amount: amount), stats: stats)[0])
    }
    #expect(mads[0] > mads[1] && mads[1] > mads[2], "\(mads)")
    #expect(mads[2] < mads[0] / 2)

    let centre = 20 * Self.width + 24
    var star = flat
    for index in 0..<count {
      let (dx, dy) = (Double(index % Self.width - 24), Double(index / Self.width - 20))
      star[0][index] += Float(0.5 * exp(-(dx * dx + dy * dy) / 2))
    }
    let protected = try Self.render(
      star, values: DenoiseOracle.Values(strengths: [5, 5, 5, 5], protectStars: true),
      stats: stats)
    #expect(Double(protected[0][centre] - 0.1) >= 0.95 * Double(star[0][centre] - 0.1))
    let bare = try Self.render(
      star, values: DenoiseOracle.Values(strengths: [5, 5, 5, 5]), stats: stats)
    #expect(bare[0][centre] < protected[0][centre], "the protection is what keeps the peak")
  }

  @Test("passes every contract, with the stars protected or not")
  func testContracts() throws {
    let contracts = try ProcessContractTests.contracts()
    for protect in [false, true] {
      let params = try Self.params(DenoiseOracle.Values(amount: 0.8, protectStars: protect))
      #expect(try contracts.violations(of: DenoiseProcess.self, params: params).isEmpty)
    }
  }

  @Test("a linear process, registered right after colour calibration")
  func testRegistered() throws {
    let ids = try ProcessRegistry.standard().ids
    let index = try #require(ids.firstIndex(of: DenoiseProcess.id))
    #expect(ids[index - 1] == ColourCalibrationProcess.id)
    #expect(DenoiseProcess.stage == .linear && DenoiseProcess.previewExactOnlyAt1to1)
  }

  @Test("only the star protection reads the stats (the median); without it none are needed")
  func testStats_OnlyTheProtectionNeedsThem() throws {
    let planes = Self.field(channels: 1)
    let none = LayerStats(channels: [])
    #expect(throws: ProcessError.self) {
      try Self.render(planes, values: DenoiseOracle.Values(protectStars: true), stats: none)
    }
    #expect(try Self.render(planes, values: DenoiseOracle.Values(), stats: none) != planes)
    #expect(
      try Self.render(planes, values: DenoiseOracle.Values(amount: 0), stats: none) == planes)
  }

  @Test("the thresholds follow the noise level shown, never the image's MADN")
  func testThresholds_FollowTheNoiseLevel() throws {
    let planes = Self.field()
    let wide = LayerStats(
      channels: Self.stats.channels.map {
        ChannelStats(median: $0.median, madn: 0.2, minimum: 0, maximum: 1)
      })
    let values = DenoiseOracle.Values()
    #expect(
      try Self.render(planes, values: values, stats: wide) == Self.render(planes, values: values))
    #expect(
      try Self.render(planes, values: DenoiseOracle.Values(noise: 0)) == planes,
      "a noise level of 0 thresholds nothing")
  }

  @Test(
    "nothing to threshold or nothing kept copies the input bit for bit",
    arguments: [
      DenoiseOracle.Values(strengths: [0, 0, 0, 0]),
      DenoiseOracle.Values(luminance: 0, chrominance: 0),
    ])
  func testIdentity_NothingToDo(values: DenoiseOracle.Values) throws {
    let planes = Self.field()
    #expect(try Self.render(planes, values: values) == planes)
    var mono = values
    mono.chrominance = 1
    if values.luminance == 0 {
      let plane = Self.field(channels: 1)
      #expect(try Self.render(plane, values: mono) == plane, "mono reads the luminance only")
    }
  }

  @Test("an image of 2 planes is refused, not half blended")
  func testPlanes_OneOrThree() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let planes = Array(Self.field().prefix(2))
    let input = try GPUImage(device: device, width: Self.width, height: Self.height, planes: planes)
    let process = try DenoiseProcess(params: Self.params(DenoiseOracle.Values()), device: device)
    #expect(throws: ProcessError.sizeMismatch) {
      try ProcessRunner(device: device).run(process, input: input, stats: Self.stats)
    }
  }
}

extension DenoiseProcessTests {
  @Test("the measured noise is offered as the noise level (median of the planes), never applied")
  func testSuggestion_MeasuredNoise() throws {
    let reason = DenoiseProcess.suggestionReasons[0]
    #expect(
      DenoiseProcess.suggestions(measured: [0.004, 0.0123456, 0.005]) == [
        Suggestion(paramID: "noise", value: .number(0.005), reason: reason)
      ])
    #expect(
      DenoiseProcess.suggestions(measured: [0.0123456]) == [
        Suggestion(paramID: "noise", value: .number(0.01235), reason: reason)
      ])
    #expect(DenoiseProcess.suggestions(measured: [0, .nan]).isEmpty)
    #expect(DenoiseProcess.suggestions(measured: []).isEmpty)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let params = ParamSet(schema: DenoiseProcess.schema)
    let process = try DenoiseProcess(params: params, device: device)
    #expect(process.suggestions(stats: Self.stats).isEmpty, "nothing measured from the stats")
    #expect(params.number("noise") == 0, "no noise level until the user sets or takes one")
  }
}
