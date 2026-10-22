import Metal
import ProcessKit
import Testing

/// The four colour processes of card 0053 against the shared contracts, and their registration.
@Suite(
  "Colour processes: contracts and registration",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ColourContractTests {
  static let stats = LayerStats(
    channels: Array(
      repeating: ChannelStats(median: 0.3, madn: 0.01, minimum: 0, maximum: 1), count: 3))

  static func contracts(planes: [[Float]] = ColourFixtures.field()) throws -> ProcessContracts {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(
      device: device, width: ColourFixtures.width, height: ColourFixtures.height, planes: planes)
    return try ProcessContracts(device: device, input: input, stats: stats)
  }

  static func params<P: ImageProcess>(_ type: P.Type, _ values: [String: ParamValue]) throws
    -> ParamSet
  {
    var params = ParamSet(schema: P.schema)
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  static let sShape = ParamValue.points([
    CurvePoint(0, 0), CurvePoint(0.3, 0.2), CurvePoint(0.7, 0.85), CurvePoint(1, 1),
  ])

  @Test("each colour process passes every contract, colour and mono")
  func testContracts() throws {
    let cases: [(any ImageProcess.Type, ParamSet)] = [
      (
        SaturationProcess.self,
        try Self.params(
          SaturationProcess.self,
          ["amount": .number(0.32), "starDesat": .number(0.25), "lumaDesat": .number(0.62)])
      ),
      (
        CurvesProcess.self,
        try Self.params(CurvesProcess.self, ["rgb": Self.sShape, "saturation": Self.sShape])
      ),
      (
        ColourBalanceProcess.self,
        try Self.params(
          ColourBalanceProcess.self, ["offsetRed": .number(-0.02), "gainBlue": .number(1.3)])
      ),
      (
        SkyDesatProcess.self,
        try Self.params(
          SkyDesatProcess.self,
          ["strength": .number(1), "keepCool": .flag(true), "scalePx": .number(8)])
      ),
    ]
    let field = ColourFixtures.field()
    for planes in [field, [field[1]]] {
      let contracts = try Self.contracts(planes: planes)
      for (type, params) in cases {
        let violations = try contracts.violations(of: type, params: params)
        #expect(violations.isEmpty, "\(type.id) ×\(planes.count): \(violations)")
      }
    }
  }

  @Test("the Studio lists them after the stretch, each in its stage")
  func testRegistered() throws {
    let registry = try ProcessRegistry.standard()
    #expect(
      registry.ids == [
        "channel-combination", "stretch", "levels", "hdr", "emission-screens", "colour-balance",
        "sky-desat", "curves", "saturation", "star-recomposition",
      ])
    #expect(ColourBalanceProcess.stage == .linear && SkyDesatProcess.stage == .linear)
    #expect(CurvesProcess.stage == .nonlinear && SaturationProcess.stage == .nonlinear)
  }
}
