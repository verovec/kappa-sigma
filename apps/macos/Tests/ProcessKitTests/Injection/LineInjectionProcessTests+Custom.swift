import Metal
import ProcessKit
import Testing

/// Card 0164: a line layer kept as written (`Filter5`) gets an « Other line k » card — a static
/// slot whose layer parameter names it — and injects like a catalogued line.
extension LineInjectionProcessTests {
  /// The bundle plus two custom line layers.
  static let customPlanes = planes.merging([
    "Filter5": [plane(seed: 31, in: 0...0.3)],
    "NII-custom": [plane(seed: 32, in: 0...0.2)],
  ]) { $1 }

  /// `values` (numbers) on the defaults, with slot `k` bound to each named layer.
  static func params(_ values: [String: Double], slots: [Int: String]) throws -> ParamSet {
    var params = try Self.params(values)
    for (slot, layer) in slots { try params.set("custom\(slot)Layer", .choice(layer)) }
    return params
  }

  /// Runs the process on `customPlanes`' RGB base.
  static func render(_ params: ParamSet) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = try customPlanes.mapValues {
      try GPUImage(device: device, width: width, height: height, planes: $0)
    }
    return try ProcessRunner(device: device).run(
      LineInjectionProcess(params: params, device: device),
      input: try GPUImage(
        device: device, width: width, height: height, planes: planes["RGB"] ?? []),
      stats: LayerStats(channels: []), layers: layers, layerStats: layerStats, mask: nil
    ).read()
  }

  @Test("an « Other line » slot injects its layer like a catalogued line (CPU oracle, ≤ 1e-6)")
  func testCustomSlot_InjectsLikeACatalogLine() throws {
    let params = try Self.params(
      ["haGain": 1, "custom1Gain": 1.5, "custom1Green": 0, "custom1Black": 0.02],
      slots: [1: "Filter5"])
    var lines = try LineInjectionOracle.lines(
      params: params, planes: Self.customPlanes, references: Self.references)
    let custom = try #require(Self.customPlanes["Filter5"]?[0])
    lines.append(
      LineInjectionOracle.Line(
        plane: custom, reference: custom, gain: 1.5, shares: [1, 0, 1], k: 0, black: 0.02))
    let expected = LineInjectionOracle.inject(Self.planes["RGB"] ?? [], lines: lines)
    let out = try Self.render(params)
    let deltas = zip(out.joined(), expected.joined()).map { abs(Double($0) - Double($1)) }
    #expect(deltas.count == 3 * Self.width * Self.height)
    #expect(deltas.max() ?? .infinity <= 1e-6)
  }

  @Test(
    "a slot at its defaults, or bound with gain 0, changes no bit",
    arguments: [[:], [1: "Filter5"], [1: "Filter5", 2: "NII-custom"]] as [[Int: String]])
  func testCustomSlot_DefaultsAreIdentity(slots: [Int: String]) throws {
    let out = try Self.render(try Self.params([:], slots: slots))
    #expect(out == Self.planes["RGB"])
  }

  @Test("a slot lists the bundle's custom line layers only, none first")
  func testCustomSlot_OptionsAreCustomLineLayers() throws {
    let spec = try #require(LineInjectionProcess.schema.spec("custom1Layer"))
    let options = LineInjectionProcess.layerOptions(
      for: spec,
      planes: ["RGB": 3, "L": 1, "Ha": 1, "OIII": 1, "Filter5": 1, "NII-custom": 1, "mask": 1])
    #expect(options == ["none", "Filter5", "NII-custom"])
  }

  /// One bundle and slot binding, with the rows that must hide and those that must show.
  struct RowsCase: Sendable {
    let layerIDs: Set<String>
    var slots: [Int: String] = [:]
    let hidden: Set<String>
    let shown: Set<String>
  }

  @Test(
    "slot rows: the picker shows once the bundle has that many custom layers, the rows once bound",
    arguments: [
      RowsCase(
        layerIDs: ["RGB", "Ha"], hidden: ["custom1Layer", "custom1Gain", "custom2Layer"],
        shown: []),
      RowsCase(
        layerIDs: ["RGB", "Ha", "Filter5"], hidden: ["custom1Gain", "custom2Layer"],
        shown: ["custom1Layer"]),
      RowsCase(
        layerIDs: ["RGB", "Filter5"], slots: [1: "Filter5"], hidden: ["custom2Layer"],
        shown: ["custom1Layer", "custom1Gain"]),
      RowsCase(
        layerIDs: ["RGB", "Filter5", "NII-custom"], hidden: ["custom3Layer"],
        shown: ["custom1Layer", "custom2Layer"]),
    ])
  func testCustomSlot_RowsHiddenUntilOffered(row: RowsCase) throws {
    let rows = LineInjectionProcess.hiddenParameters(
      try Self.params([:], slots: row.slots), layerIDs: row.layerIDs)
    #expect(row.hidden.isSubset(of: rows))
    #expect(row.shown.isDisjoint(with: rows))
  }

  @Test("a bound slot whose layer is absent keeps its rows when its gain asks, with the reason")
  func testCustomSlot_AbsentLayerIsNoted() throws {
    let params = try Self.params(["custom1Gain": 1], slots: [1: "Filter5"])
    let layerIDs: Set<String> = ["RGB", "Ha"]
    #expect(
      !LineInjectionProcess.hiddenParameters(params, layerIDs: layerIDs).contains("custom1Gain"))
    let note = try #require(
      LineInjectionProcess.unavailableReasons(params, layerIDs: layerIDs)["custom1Layer"])
    #expect(note.reason == LineInjectionProcess.lineLayerReason)
    #expect(LineInjectionProcess.layersRead(params, layerIDs: ["RGB", "Filter5"]) == ["Filter5"])
  }

  @Test("two lines on one layer are refused, never added twice")
  func testCustomSlot_DuplicateLayerRefused() throws {
    let params = try Self.params(
      ["custom1Gain": 1, "custom2Gain": 1], slots: [1: "Filter5", 2: "Filter5"])
    #expect(throws: ProcessError.self) { try Self.render(params) }
  }

  @Test(
    "a slot naming a catalogued or broadband layer is refused, never read as a line",
    arguments: ["Ha", "RGB"])
  func testCustomSlot_OnlyCustomLineLayers(layer: String) throws {
    let params = try Self.params(["custom1Gain": 1], slots: [1: layer])
    #expect(throws: ProcessError.self) { try Self.render(params) }
  }

  @Test("a bound slot round-trips through stored values, nothing rejected")
  func testCustomSlot_StoredValuesReload() throws {
    let params = try Self.params(["custom1Gain": 2], slots: [1: "Filter5"])
    let stored = params.ids.compactMap { id in params[id].map { ParamSet.Entry(id: id, value: $0) }
    }
    let (loaded, rejected) = ParamSet.loading(stored, onto: LineInjectionProcess.schema)
    #expect(rejected.isEmpty)
    #expect(loaded == params)
  }
}
