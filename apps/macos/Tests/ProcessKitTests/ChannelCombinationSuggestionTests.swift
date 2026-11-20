import Metal
import ProcessKit
import Testing

/// Card 0171: a step 0 that is a grey, or that reads a layer the stack lacks, is offered the
/// combination the stack opens on — never rewritten (R2).
@Suite("ChannelCombination suggestions: the palette the layers spell, offered, never applied")
struct ChannelCombinationSuggestionTests {
  /// One row: the step's R, G, B, L sources, the bundle's planes, the sources offered by slot.
  struct Case: Sendable, CustomTestStringConvertible {
    let sources: [String]
    let planes: [String: Int]
    let offered: [String: String]
    let subject: String?
    var testDescription: String {
      "\(sources.joined(separator: ",")) on \(planes.keys.sorted().joined(separator: "/"))"
    }
  }

  static func mono(_ ids: String...) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: ids.map { ($0, 1) })
  }

  static func params(_ sources: [String]) throws -> ParamSet {
    var params = ParamSet(schema: ChannelCombinationProcess.schema)
    try ChannelCombinationProcess.set(sources: sources, on: &params)
    return params
  }

  static func offered(_ suggestions: [Suggestion]) -> [String: String] {
    var offered: [String: String] = [:]
    for suggestion in suggestions {
      if case .choice(let source) = suggestion.value { offered[suggestion.paramID] = source }
    }
    return offered
  }

  @Test(
    "a grey step is offered the palette the layers spell, one suggestion per slot that changes",
    arguments: [
      Case(
        sources: ["L", "L", "L", "none"], planes: mono("L", "R", "G", "B", "Ha"),
        offered: ["rSource": "R", "gSource": "G", "bSource": "B", "lSource": "L"],
        subject: "LRGB"),
      Case(
        sources: ["L", "L", "L", "none"], planes: mono("R", "G", "B"),
        offered: ["rSource": "R", "gSource": "G", "bSource": "B"], subject: "RGB"),
      Case(
        sources: ["R", "R", "R", "none"], planes: mono("R", "G", "B"),
        offered: ["gSource": "G", "bSource": "B"], subject: "RGB"),
      Case(
        sources: ["L", "L", "L", "none"], planes: mono("Ha", "OIII", "SII"),
        offered: ["rSource": "SII", "gSource": "Ha", "bSource": "OIII"], subject: "SHO"),
      Case(
        sources: ["Ha", "Ha", "Ha", "none"], planes: mono("Ha", "OIII"),
        offered: ["gSource": "OIII", "bSource": "OIII"], subject: "HOO"),
      // L stays a choice on a line palette: a luminance the stack holds is not offered away.
      Case(
        sources: ["L", "L", "L", "L"], planes: mono("L", "Ha", "OIII"),
        offered: ["rSource": "Ha", "gSource": "OIII", "bSource": "OIII"], subject: "HOO"),
    ])
  func testSuggestions_GreyStepOnLRGBLayers(row: Case) throws {
    let suggestions = ChannelCombinationProcess.sourceSuggestions(
      try Self.params(row.sources), planes: row.planes)
    #expect(Self.offered(suggestions) == row.offered)
    #expect(suggestions.count == row.offered.count, "no parameter offered twice")
    #expect(Set(suggestions.map(\.reason)) == [ChannelCombinationProcess.spelledReason])
    #expect(Set(suggestions.map(\.subject)) == [row.subject])
  }

  @Test(
    "a step reading a layer the stack lacks is offered sources the stack holds",
    arguments: [
      // The PO's Orion stack (card 0170): a kept LRGB profile on L + Hα. No palette is spelled:
      // only the slots that cannot run move, to what the stack opens on; L is kept.
      Case(
        sources: ["R", "G", "B", "L"], planes: mono("L", "Ha"),
        offered: ["rSource": "L", "gSource": "L", "bSource": "L"], subject: nil),
      // A palette is spelled: every slot goes to it, never a mix of two palettes.
      Case(
        sources: ["SII", "Ha", "OIII", "none"], planes: mono("L", "R", "G", "B", "Ha"),
        offered: ["rSource": "R", "gSource": "G", "bSource": "B", "lSource": "L"],
        subject: "LRGB"),
      // A colour bundle: the planes of the colour layer, and no luminance left on a lost layer.
      Case(
        sources: ["R", "G", "B", "L"], planes: ["RGB": 3, "Ha": 1],
        offered: [
          "rSource": "RGB.r", "gSource": "RGB.g", "bSource": "RGB.b", "lSource": "none",
        ], subject: nil),
    ])
  func testSuggestions_MissingLayerSlots(row: Case) throws {
    let params = try Self.params(row.sources)
    let suggestions = ChannelCombinationProcess.sourceSuggestions(params, planes: row.planes)
    #expect(Self.offered(suggestions) == row.offered)
    #expect(Set(suggestions.map(\.subject)) == [row.subject])
    let reason =
      row.subject == nil
      ? ChannelCombinationProcess.lackingReason : ChannelCombinationProcess.spelledReason
    #expect(Set(suggestions.map(\.reason)) == [reason])
    // Taking them all leaves no slot on a layer the stack lacks.
    var taken = params
    for suggestion in suggestions { try taken.set(suggestion.paramID, suggestion.value) }
    #expect(
      ChannelCombinationProcess.unavailableReasons(taken, layerIDs: Set(row.planes.keys)).isEmpty)
  }

  @Test(
    "nothing is offered to a step that already renders in colour, or when no palette is spelled",
    arguments: [
      // OSC with the schema's defaults: the panel of every colour stack is unchanged.
      Case(
        sources: ["RGB.r", "RGB.g", "RGB.b", "none"], planes: ["RGB": 3], offered: [:],
        subject: nil),
      Case(
        sources: ["RGB.r", "RGB.g", "RGB.b", "none"], planes: ["RGB": 3, "Ha": 1, "OIII": 1],
        offered: [:], subject: nil),
      // A grey of one plane of a colour layer is the user's choice, the layer holds the colour.
      Case(
        sources: ["RGB.g", "RGB.g", "RGB.g", "none"], planes: ["RGB": 3], offered: [:],
        subject: nil),
      Case(
        sources: ["R", "G", "B", "L"], planes: mono("L", "R", "G", "B", "Ha"), offered: [:],
        subject: nil),
      // A custom colour combination of layers the stack holds is left alone.
      Case(
        sources: ["Ha", "G", "B", "L"], planes: mono("L", "R", "G", "B", "Ha"), offered: [:],
        subject: nil),
      // Another palette the layers allow is a choice, not a leftover: HOO, Foraxx on SHO layers.
      Case(
        sources: ["Ha", "OIII", "OIII", "none"], planes: mono("Ha", "OIII", "SII"),
        offered: [:], subject: nil),
      Case(
        sources: ["Ha", "Ha*OIII", "OIII", "none"], planes: mono("Ha", "OIII", "SII"),
        offered: [:], subject: nil),
      // The three planes of one colour layer are a colour image, whatever the layer's name.
      Case(
        sources: ["X.r", "X.g", "X.b", "none"], planes: ["X": 3, "Ha": 1, "OIII": 1],
        offered: [:], subject: nil),
      Case(sources: ["L", "L", "L", "none"], planes: mono("L"), offered: [:], subject: nil),
      Case(
        sources: ["Ha", "Ha", "Ha", "none"], planes: mono("L", "Ha"), offered: [:], subject: nil),
      Case(sources: ["L", "L", "L", "none"], planes: [:], offered: [:], subject: nil),
    ])
  func testSuggestions_None(row: Case) throws {
    let suggestions = ChannelCombinationProcess.sourceSuggestions(
      try Self.params(row.sources), planes: row.planes)
    #expect(suggestions.isEmpty)
  }

  @Test(
    "taking one suggestion keeps the others offered: a half-taken palette is never a dead end",
    arguments: [
      Case(
        sources: ["R", "L", "L", "none"], planes: mono("L", "R", "G", "B", "Ha"),
        offered: ["gSource": "G", "bSource": "B", "lSource": "L"], subject: "LRGB"),
      Case(
        sources: ["R", "G", "L", "none"], planes: mono("L", "R", "G", "B", "Ha"),
        offered: ["bSource": "B", "lSource": "L"], subject: "LRGB"),
      Case(
        sources: ["R", "G", "R", "none"], planes: mono("R", "G", "B"),
        offered: ["bSource": "B"], subject: "RGB"),
      Case(
        sources: ["SII", "Ha", "Ha", "none"], planes: mono("Ha", "OIII", "SII"),
        offered: ["bSource": "OIII"], subject: "SHO"),
    ])
  func testSuggestions_PartialTake(row: Case) throws {
    let suggestions = ChannelCombinationProcess.sourceSuggestions(
      try Self.params(row.sources), planes: row.planes)
    #expect(Self.offered(suggestions) == row.offered)
    #expect(Set(suggestions.map(\.subject)) == [row.subject])
  }

  @Test("the weights, black points and L opacity are never part of the offer")
  func testSuggestions_OnlySources() throws {
    var params = try Self.params(["L", "L", "L", "none"])
    try params.set("rWeight", .number(2))
    try params.set("gBlack", .number(0.01))
    try params.set("lOpacity", .number(0.5))
    let suggestions = ChannelCombinationProcess.sourceSuggestions(
      params, planes: Self.mono("L", "R", "G", "B"))
    #expect(Set(suggestions.map(\.paramID)).isSubset(of: ChannelCombinationProcess.slotSources))
  }

  @Test(
    "asking changes nothing: the process keeps its values, layers are read by plane count",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testSuggestions_NotApplied() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let params = try Self.params(["L", "L", "L", "none"])
    let process = try ChannelCombinationProcess(params: params, device: device)
    let plane = ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1)
    let layers = Dictionary(
      uniqueKeysWithValues: ["L", "R", "G", "B", "Ha"].map {
        ($0, LayerStats(channels: [plane]))
      })
    let suggestions = process.suggestions(stats: LayerStats(channels: []), layers: layers)
    #expect(
      Self.offered(suggestions) == [
        "rSource": "R", "gSource": "G", "bSource": "B", "lSource": "L",
      ])
    #expect(process.params == params)
    #expect(
      suggestions.map(\.reason).allSatisfy(ChannelCombinationProcess.suggestionReasons.contains))
    // A step output (a starless, a background model) is no colour source: never offered.
    var withOutputs = ["uvir": LayerStats(channels: [plane])]
    for role in LayerRole.allCases { withOutputs[role.rawValue] = LayerStats(channels: [plane]) }
    let lacking = try ChannelCombinationProcess(
      params: Self.params(["R", "G", "B", "none"]), device: device)
    #expect(
      Self.offered(lacking.suggestions(stats: LayerStats(channels: []), layers: withOutputs))
        == ["rSource": "uvir", "gSource": "uvir", "bSource": "uvir"])
    // A colour layer is three planes: the same ids as a colour bundle offer nothing.
    let colour = ["RGB": LayerStats(channels: [plane, plane, plane])]
    let natural = try ChannelCombinationProcess(
      params: ParamSet(schema: ChannelCombinationProcess.schema), device: device)
    #expect(natural.suggestions(stats: LayerStats(channels: []), layers: colour).isEmpty)
  }
}
