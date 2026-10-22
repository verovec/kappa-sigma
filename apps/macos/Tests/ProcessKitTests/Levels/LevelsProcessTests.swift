import Metal
import ProcessKit
import RenderKit
import Testing

/// `LevelsProcess` (card 0089): the kernel against a float mirror of the shared `stf`, that
/// mirror against `MTF.apply`, the identity defaults, the contracts and the refused values.
@Suite(
  "Histogram transformation: shared MTF, identity defaults, contracts",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct LevelsProcessTests {
  /// One table row: the panel values and whether the image is colour.
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let values: [String: ParamValue]
    let colour: Bool
    var testDescription: String { name }
  }

  /// Random c0 < m < c1 per triple from `seed` (m relative, as the panel holds it).
  static func triple(_ prefix: String, seed: inout UInt32) -> [String: ParamValue] {
    func next() -> Double {
      seed = seed &* 1_664_525 &+ 1_013_904_223
      return Double(seed >> 8) / Double(1 << 24)
    }
    let c0 = next() * 0.3
    let c1 = 0.6 + next() * 0.4
    return [
      prefix + "Shadows": .number(c0), prefix + "Midtones": .number(0.05 + next() * 0.9),
      prefix + "Highlights": .number(c1),
    ]
  }

  static let cases: [Case] = {
    var seed: UInt32 = 89
    var cases: [Case] = []
    for colour in [true, false] {
      let linked = triple("rgb", seed: &seed)
      cases.append(Case(name: "linked \(colour)", values: linked, colour: colour))
      var unlinked = linked.merging(["linked": .flag(false)]) { $1 }
      for prefix in ["r", "g", "b"] { unlinked.merge(triple(prefix, seed: &seed)) { $1 } }
      cases.append(Case(name: "unlinked \(colour)", values: unlinked, colour: colour))
      let output = unlinked.merging(["outputLow": .number(0.1), "outputHigh": .number(0.85)]) {
        $1
      }
      cases.append(Case(name: "unlinked + output \(colour)", values: output, colour: colour))
    }
    return cases
  }()

  /// The float arithmetic of `STF.h`'s `mtf`, as the Metal compiler emits it: the denominator
  /// (2m − 1)·x − m is one fused multiply-add.
  static func mtf(_ midtone: Float, _ x: Float) -> Float {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    if x == midtone { return 0.5 }
    return ((midtone - 1) * x) / (-midtone).addingProduct(2 * midtone - 1, x)
  }

  /// The float arithmetic of `STF.h`'s `stf`.
  static func stf(_ x: Float, _ stf: STFParameters) -> Float {
    let (c0, midtone, c1) = (Float(stf.shadows), Float(stf.midtone), Float(stf.highlights))
    let range = c1 - c0
    if range <= 0 { return x >= c1 ? 1 : 0 }
    return mtf(midtone, min(max((x - c0) / range, 0), 1))
  }

  /// The CPU oracle of the kernel: each channel's triple when unlinked, the RGB/K triple, the
  /// output range; an identity triple skipped.
  static func oracle(_ planes: [[Float]], _ params: ParamSet) -> [[Float]] {
    let unlinked = !params.flag("linked") && planes.count == 3
    let (low, high) = (Float(params.number("outputLow")), Float(params.number("outputHigh")))
    return planes.enumerated().map { channel, plane in
      plane.map { x in
        var value = x
        let own = LevelsProcess.stf(["r", "g", "b"][channel], of: params)
        if unlinked, own != .identity { value = stf(value, own) }
        let rgb = LevelsProcess.stf("rgb", of: params)
        if rgb != .identity { value = stf(value, rgb) }
        if low != 0 || high != 1 { value = low.addingProduct(value, high - low) }
        return value
      }
    }
  }

  static func params(_ values: [String: ParamValue]) throws -> ParamSet {
    var params = ParamSet(schema: LevelsProcess.schema)
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  @Test("the kernel equals the float mirror of the shared stf, bit for bit", arguments: cases)
  func testMatchesMTFOracle(row: Case) throws {
    let field = ColourFixtures.field()
    let planes = row.colour ? field : [field[1]]
    let out = try ColourFixtures.run(LevelsProcess.self, row.values, planes: planes)
    let expected = Self.oracle(planes, try Self.params(row.values))
    for (got, want) in zip(out.joined(), expected.joined()) {
      #expect(got.bitPattern == want.bitPattern, "\(got) vs \(want)")
    }
  }

  @Test("the float mirror is MTF.apply in double, to float rounding")
  func testMirrorIsMTFApply() {
    var worst = 0.0
    for midtone in stride(from: 0.02, through: 0.98, by: 0.06) {
      for x in stride(from: 0.0, through: 1, by: 1.0 / 257) {
        let mirrored = Double(Self.mtf(Float(midtone), Float(x)))
        let exact = MTF.apply(Double(Float(midtone)), Double(Float(x)))
        worst = max(worst, abs(mirrored - exact))
      }
    }
    #expect(worst <= 1e-6, "max |float − double| = \(worst)")
  }

  @Test("untouched values return the input bit for bit, out-of-range values included")
  func testDefaultsAreIdentity() throws {
    var field = ColourFixtures.field()
    field[0][0] = -0.25
    field[1][1] = 1.75
    field[2][2] = .nan
    for planes in [field, [field[1]]] {
      let out = try ColourFixtures.run(LevelsProcess.self, [:], planes: planes)
      #expect(out.joined().map(\.bitPattern) == planes.joined().map(\.bitPattern))
      // Unlinked with every triple at its default changes nothing either.
      let unlinked = try ColourFixtures.run(
        LevelsProcess.self, ["linked": .flag(false)], planes: planes)
      #expect(unlinked.joined().map(\.bitPattern) == planes.joined().map(\.bitPattern))
    }
  }

  @Test("levels pass every contract, colour and mono, linked and not")
  func testContracts() throws {
    let field = ColourFixtures.field()
    for planes in [field, [field[1]]] {
      let contracts = try ColourContractTests.contracts(planes: planes)
      for row in Self.cases where row.colour == (planes.count == 3) {
        let violations = try contracts.violations(
          of: LevelsProcess.self, params: try Self.params(row.values))
        #expect(violations.isEmpty, "\(row.name): \(violations)")
      }
    }
  }

  @Test("shadows at or above the highlights are refused with the reason, never adjusted")
  func testRefusesCrossedPoints() throws {
    #expect(throws: ProcessError.self) {
      _ = try ColourFixtures.run(
        LevelsProcess.self, ["rgbShadows": .number(0.6), "rgbHighlights": .number(0.4)],
        planes: ColourFixtures.field())
    }
    // A crossed per-channel triple counts only once it applies (unlinked).
    let linked = try ColourFixtures.run(
      LevelsProcess.self, ["rShadows": .number(0.6), "rHighlights": .number(0.4)],
      planes: ColourFixtures.field())
    #expect(linked == ColourFixtures.field())
  }

  @Test("Siril's autostretch is a suggestion of the three RGB/K values, one reason")
  func testAutostretchSuggestion() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let process = try LevelsProcess(params: try Self.params([:]), device: device)
    let stats = LayerStats(
      channels: [
        ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1),
        ChannelStats(median: 0.12, madn: 0.012, minimum: 0, maximum: 1),
        ChannelStats(median: 0.08, madn: 0.008, minimum: 0, maximum: 1),
      ])
    let mapping = STFMapping.linked(
      stats.channels.map { STFMapping(median: $0.median, madn: $0.madn) })[0]
    let stf = mapping.parameters(sigma: -2.8, targetBackground: 0.25)
    let suggestions = process.suggestions(stats: stats)
    #expect(suggestions.map(\.paramID) == ["rgbShadows", "rgbMidtones", "rgbHighlights"])
    #expect(suggestions.map(\.value) == [.number(stf.shadows), .number(stf.midtone), .number(1)])
    #expect(Set(suggestions.map(\.reason)) == [LevelsProcess.suggestionReasons[0]])
    #expect(process.suggestions(stats: LayerStats(channels: [])).isEmpty)
  }

  @Test("unlinked channels promote their triples; linked shows them behind the disclosure")
  func testPromotion() throws {
    #expect(LevelsProcess.promoted(try Self.params([:])).isEmpty)
    let promoted = LevelsProcess.promoted(try Self.params(["linked": .flag(false)]))
    #expect(promoted.count == 9 && promoted.contains("bMidtones"))
    let visible = LevelsProcess.schema.visible(disclosed: false, promoted: promoted).map(\.id)
    #expect(visible.contains("rShadows") && !visible.contains("outputLow"))
  }
}
