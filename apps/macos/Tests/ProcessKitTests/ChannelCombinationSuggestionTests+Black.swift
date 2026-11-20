import Metal
import ProcessKit
import Testing

/// Card 0172: each slot's black point is offered just under the sky its layer measures on the
/// stack (median − 2.8 MADN, the autostretch's shadows), never set (R2) — the defaults stay 0 and
/// step 0 keeps its bytes.
extension ChannelCombinationSuggestionTests {
  /// Bundle statistics with `medians` per layer, one entry per plane, each with the noise `madn`.
  static func stats(_ medians: [String: [Double]], madn: Double = 0) -> [String: LayerStats] {
    medians.mapValues { planes in
      LayerStats(
        channels: planes.map {
          ChannelStats(median: $0, madn: madn, minimum: 0, maximum: 1)
        })
    }
  }

  /// The schema's defaults with `sources` in the R, G, B, L slots and `blacks` set.
  static func params(sources: [String], blacks: [String: Double] = [:]) throws -> ParamSet {
    var params = ParamSet(schema: ChannelCombinationProcess.schema)
    try ChannelCombinationProcess.set(sources: sources, on: &params)
    for (id, value) in blacks { try params.set(id, .number(value)) }
    return params
  }

  /// The black suggestions `ids` at `values`, as the process words them.
  static func expected(_ ids: [String], _ values: [Double]) -> [Suggestion] {
    zip(ids, values).map {
      Suggestion(
        paramID: $0, value: .number($1), reason: ChannelCombinationProcess.skyBlackReason)
    }
  }

  /// `suggestions` are the row's: its ids in slot order, its values within 1e-12 (a median less
  /// a multiple of the noise is not a literal), the one reason.
  static func expect(_ suggestions: [Suggestion], _ row: Row) {
    #expect(suggestions.map(\.paramID) == row.ids)
    for (suggestion, value) in zip(suggestions, row.values) {
      #expect(suggestion.reason == ChannelCombinationProcess.skyBlackReason)
      guard case .number(let offered) = suggestion.value else {
        Issue.record("\(suggestion.paramID) is not a number")
        continue
      }
      #expect(abs(offered - value) <= 1e-12, "\(suggestion.paramID): \(offered)")
    }
  }

  struct Row: CustomTestStringConvertible, Sendable {
    let name: String
    let sources: [String]
    var blacks: [String: Double] = [:]
    let medians: [String: [Double]]
    var madn: Double = 0
    let ids: [String]
    let values: [Double]
    var testDescription: String { name }
  }

  /// The PO's M42 mono stack, as card 0170 read it: the skies that tint the composite magenta.
  static let m42 = [
    "L": [0.1596], "R": [0.02322], "G": [0.00860], "B": [0.02423], "Ha": [0.00183],
  ]

  static let blacksOffered: [Row] = [
    Row(
      name: "LRGB at the M42 skies of 0170", sources: ["R", "G", "B", "L"], medians: m42,
      ids: ["rBlack", "gBlack", "bBlack", "lBlack"], values: [0.02322, 0.00860, 0.02423, 0.1596]),
    Row(
      name: "RGB without luminance: three slots", sources: ["R", "G", "B", "none"], medians: m42,
      ids: ["rBlack", "gBlack", "bBlack"], values: [0.02322, 0.00860, 0.02423]),
    Row(
      name: "SHO: each line's own sky", sources: ["SII", "Ha", "OIII", "none"],
      medians: ["SII": [0.004], "Ha": [0.00183], "OIII": [0.006]],
      ids: ["rBlack", "gBlack", "bBlack"], values: [0.004, 0.00183, 0.006]),
    Row(
      name: "2.8 σ of the layer's noise under its sky: the sky itself is not clipped",
      sources: ["R", "G", "B", "L"], medians: m42, madn: 0.001,
      ids: ["rBlack", "gBlack", "bBlack", "lBlack"],
      values: [0.02042, 0.00580, 0.02143, 0.1568]),
    Row(
      name: "a black set for another source is offered this one's",
      sources: ["Ha", "G", "B", "none"], blacks: ["rBlack": 0.02322], medians: m42,
      ids: ["rBlack", "gBlack", "bBlack"], values: [0.00183, 0.00860, 0.02423]),
    Row(
      name: "a sky above the range is clamped to it", sources: ["R", "G", "B", "none"],
      medians: ["R": [1.4], "G": [0.5], "B": [1]],
      ids: ["rBlack", "gBlack", "bBlack"], values: [1, 0.5, 1]),
    Row(
      name: "the planes of a 3-plane layer: each plane's sky",
      sources: ["Ha 7nm.r", "Ha 7nm.g", "Ha 7nm.b", "none"],
      medians: ["Ha 7nm": [0.01, 0.02, 0.03]],
      ids: ["rBlack", "gBlack", "bBlack"], values: [0.01, 0.02, 0.03]),
  ]

  @Test("testBlackSuggestions_MonoLRGB", arguments: blacksOffered)
  func testBlackSuggestions_MonoLRGB(row: Row) throws {
    let params = try Self.params(sources: row.sources, blacks: row.blacks)
    let suggestions = ChannelCombinationProcess.blackSuggestions(
      params, layers: Self.stats(row.medians, madn: row.madn))
    Self.expect(suggestions, row)
  }

  static let blacksWithheld: [Row] = [
    Row(
      name: "an OSC bundle on its defaults", sources: ["RGB.r", "RGB.g", "RGB.b", "none"],
      medians: ["RGB": [0.02, 0.03, 0.025]], ids: [], values: []),
    Row(
      name: "an OSC bundle on HOO: a colour bundle gets none",
      sources: ["Ha", "OIII", "OIII", "none"],
      medians: ["RGB": [0.02, 0.03, 0.025], "Ha": [0.002], "OIII": [0.003]], ids: [], values: []),
    Row(
      name: "a √(A·B) slot gets none, the others theirs",
      sources: ["Ha", "Ha*OIII", "OIII", "none"], medians: ["Ha": [0.002], "OIII": [0.003]],
      ids: ["rBlack", "bBlack"], values: [0.002, 0.003]),
    Row(
      name: "a black already at its sky is not offered again", sources: ["R", "G", "B", "L"],
      blacks: ["gBlack": 0.00860], medians: m42,
      ids: ["rBlack", "bBlack", "lBlack"], values: [0.02322, 0.02423, 0.1596]),
    Row(
      name: "a noise deeper than the sky leaves the black where it is",
      sources: ["R", "G", "B", "none"], medians: m42, madn: 0.005,
      ids: ["rBlack", "bBlack"], values: [0.00922, 0.01023]),
    Row(
      name: "a layer the bundle has no statistics of", sources: ["R", "G", "B", "L"],
      medians: ["R": [0.02322], "B": [0.02423], "L": [0.1596]],
      ids: ["rBlack", "bBlack", "lBlack"], values: [0.02322, 0.02423, 0.1596]),
    Row(
      name: "a sky at or under 0 leaves the black where it is",
      sources: ["R", "G", "B", "L"],
      medians: ["R": [0], "G": [-0.001], "B": [0.02423], "L": [.nan]],
      ids: ["bBlack"], values: [0.02423]),
    Row(
      name: "a grey of one layer has no ratio to give back", sources: ["L", "L", "L", "none"],
      medians: m42, ids: [], values: []),
    Row(
      name: "a grey under a luminance: none either", sources: ["Ha", "Ha", "Ha", "L"],
      medians: m42, ids: [], values: []),
    Row(
      name: "a plane token over one averaged entry: not that plane's sky",
      sources: ["Ha.r", "Ha.g", "Ha.b", "none"], medians: ["Ha": [0.01]], ids: [], values: []),
  ]

  @Test("testBlackSuggestions_None", arguments: blacksWithheld)
  func testBlackSuggestions_None(row: Row) throws {
    let params = try Self.params(sources: row.sources, blacks: row.blacks)
    let suggestions = ChannelCombinationProcess.blackSuggestions(
      params, layers: Self.stats(row.medians, madn: row.madn))
    Self.expect(suggestions, row)
  }

  @Test(
    "testBlackSuggestions_NotApplied: the process offers them and keeps its params (R2)",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testBlackSuggestions_NotApplied() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let params = try ChannelCombinationProcess.initialParams(
      planes: ["L": 1, "R": 1, "G": 1, "B": 1, "Ha": 1])
    let process = try ChannelCombinationProcess(params: params, device: device)
    let suggestions = process.suggestions(
      stats: LayerStats(channels: []), layers: Self.stats(Self.m42))
    #expect(
      suggestions
        == Self.expected(
          ["rBlack", "gBlack", "bBlack", "lBlack"], [0.02322, 0.00860, 0.02423, 0.1596]))
    #expect(Set(suggestions.map(\.paramID)).count == suggestions.count, "one per parameter")
    #expect(
      suggestions.map(\.reason).allSatisfy(ChannelCombinationProcess.suggestionReasons.contains))
    #expect(process.params == params)
    for slot in ["r", "g", "b", "l"] { #expect(process.params.number(slot + "Black") == 0) }
  }

  @Test("testPromoted: a black the step subtracts is shown without the disclosure (R2)")
  func testPromoted() throws {
    let untouched = try Self.params(sources: ["R", "G", "B", "L"])
    #expect(ChannelCombinationProcess.promoted(untouched).isEmpty)
    let set = try Self.params(
      sources: ["R", "G", "B", "L"], blacks: ["gBlack": 0.004, "lBlack": 0.1])
    #expect(ChannelCombinationProcess.promoted(set) == ["gBlack", "lBlack"])
  }

  @Test(
    "testSuggestions_SourcesAndBlacksInOneList: cards 0171 and 0172 together, a parameter once",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testSuggestions_SourcesAndBlacksInOneList() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    // The blue slot reads a layer this LRGB stack lacks: its source is offered, and the blacks
    // of the slots that can be measured.
    let params = try Self.params(sources: ["R", "G", "SII", "L"])
    let process = try ChannelCombinationProcess(params: params, device: device)
    var layers = Self.stats(Self.m42)
    // A later step's output, by role: neither a source nor a sky.
    layers[LayerRole.starless.rawValue] = LayerStats(channels: [])
    let suggestions = process.suggestions(stats: LayerStats(channels: []), layers: layers)
    #expect(suggestions.map(\.paramID) == ["bSource", "rBlack", "gBlack", "lBlack"])
    #expect(Set(suggestions.map(\.paramID)).count == suggestions.count)
    #expect(
      suggestions.map(\.reason).allSatisfy(ChannelCombinationProcess.suggestionReasons.contains))
    #expect(process.params == params)
  }
}
