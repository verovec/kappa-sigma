import Metal
import ProcessKit
import Testing

/// The shared contracts every registered process must pass, checked on `DummyGain` and shown to
/// catch one deliberately misbehaving fixture each.
@Suite(
  "Process contracts: PreviewEqualsApply, NoHiddenState, PxUnitsScale",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ProcessContractTests {
  static func contracts() throws -> ProcessContracts {
    let device = try #require(MTLCreateSystemDefaultDevice())
    // A ramp along x, different per plane: a shift or a gain change shows in every pixel.
    let planes: [[Float]] = (0..<3).map { plane in
      (0..<32 * 4).map { Float($0 % 32) / 31 * (1 - Float(plane) * 0.2) }
    }
    let input = try GPUImage(device: device, width: 32, height: 4, planes: planes)
    let stats = LayerStats(channels: [ChannelStats(median: 0.5, madn: 0.01, minimum: 0, maximum: 1)]
    )
    return try ProcessContracts(device: device, input: input, stats: stats)
  }

  static func gain(_ values: [String: Double] = ["gain": 1.5, "shift": 0]) throws -> ParamSet {
    var params = ParamSet(schema: GainKernel.schema)
    for (id, value) in values { try params.set(id, .number(value)) }
    return params
  }

  @Test("DummyGain passes every contract")
  func testDummyGainPasses() throws {
    let contracts = try Self.contracts()
    #expect(try contracts.violations(of: DummyGain.self, params: Self.gain()).isEmpty)
  }

  @Test(
    "each misbehaving fixture fails its contract, and only that one",
    arguments: ProcessContracts.Contract.allCases)
  func testMisbehavingFixturesFail(contract: ProcessContracts.Contract) throws {
    let type: any ImageProcess.Type =
      switch contract {
      case .noHiddenState: HiddenStateGain.self
      case .previewEqualsApply: PreviewDriftGain.self
      case .pxUnitsScale: ScaleBlindGain.self
      }
    let violations = try Self.contracts().violations(of: type, params: Self.gain())
    #expect(violations.contains { $0.contract == contract })
    if contract != .noHiddenState {
      #expect(violations.allSatisfy { $0.contract == contract })
    }
  }

  @Test("ChannelCombination passes every contract (with the bundle layers, under a mask)")
  func testCombinationPasses() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = try CombinationTests.layers(device: device, ids: ["RGB", "Ha", "OIII"])
    let row = (0..<32).map { Float($0) / 31 }
    let input = try GPUImage(
      device: device, width: 4, height: 2,
      planes: Array(repeating: Array(row.prefix(8)), count: 3))
    let contracts = try ProcessContracts(
      device: device, input: input, stats: LayerStats(channels: []), layers: layers)
    for palette in [Palette.natural, .hoo, .foraxx] {
      #expect(
        try contracts.violations(of: ChannelCombinationProcess.self, params: palette.params())
          .isEmpty, "\(palette)")
    }
  }

  @Test("suggestions come from the bundle stats and are only suggestions")
  func testSuggestions() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let process = try DummyGain(params: Self.gain(), device: device)
    let stats = LayerStats(channels: [
      ChannelStats(median: 0.05, madn: 0.001, minimum: 0, maximum: 1)
    ])
    let suggestions = process.suggestions(stats: stats)
    #expect(
      suggestions == [
        Suggestion(paramID: "gain", value: .number(5), reason: "brings the median to 0.25")
      ])
    #expect(process.params.number("gain") == 1.5, "a suggestion never changes the params")
  }
}
