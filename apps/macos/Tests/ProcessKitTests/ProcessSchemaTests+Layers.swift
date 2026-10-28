import ProcessKit
import Testing

/// The layer hooks every process gets (card 0135): which parameters its values hide for a
/// bundle, and why a row cannot run as set — one reason per parameter, never the process greyed.
extension ProcessSchemaTests {
  @Test("a process without layer rows hides nothing and has no row reason")
  func testHiddenParameters_default() {
    let params = ParamSet(schema: StretchProcess.schema)
    #expect(StretchProcess.hiddenParameters(params, layerIDs: ["RGB"]).isEmpty)
    #expect(StretchProcess.unavailableReasons(params, layerIDs: ["RGB"]).isEmpty)
    #expect(StretchProcess.rowReasons.isEmpty)
    #expect(StretchProcess.schema.specs.allSatisfy { $0.needsLayer == nil })
    #expect(StretchProcess.layersAsked(params).isEmpty)
  }

  @Test("the line specs declare their layer; hidden iff absent and not asked for")
  func testHiddenParameters_lines() throws {
    let screens = EmissionScreensProcess.schema
    #expect(try #require(screens.spec("haEnabled")).needsLayer == "Ha")
    #expect(try #require(screens.spec("nbBlend")).needsLayer == nil)
    var params = ParamSet(schema: screens)
    // Hα and OIII are on by default: they still ask for their layer, SII, Hβ and NII do not.
    let hidden = EmissionScreensProcess.hiddenParameters(params, layerIDs: ["RGB"])
    #expect(
      hidden.allSatisfy { ["sii", "hb", "nii"].contains(where: $0.hasPrefix) } && !hidden.isEmpty)
    try params.set("haEnabled", .flag(false))
    try params.set("oiiiEnabled", .flag(false))
    let allHidden = EmissionScreensProcess.hiddenParameters(params, layerIDs: ["RGB"])
    #expect(allHidden.contains("haEnabled") && allHidden.contains("oiiiOpacity"))
    #expect(
      EmissionScreensProcess.hiddenParameters(
        params, layerIDs: ["RGB", "Ha", "OIII", "SII", "Hb", "NII"]
      ).isEmpty)
  }

  @Test("every process whose rows carry needsLayer lists a row reason (the default needs one)")
  func testRowReasons_declared() throws {
    for type in try ProcessRegistry.standard().types {
      let hasLayerRows = type.schema.specs.contains { $0.needsLayer != nil }
      #expect(!hasLayerRows || !type.rowReasons.isEmpty, "\(type.id)")
    }
  }

  /// One row per process: the values, the layers present, and the reason expected per param.
  struct Reasons: CustomTestStringConvertible, Sendable {
    let name: String
    let processID: String
    var values: [String: ParamValue] = [:]
    let layers: Set<String>
    let expected: [String: RowNote]
    var testDescription: String { name }
  }

  static let reasons: [Reasons] = [
    Reasons(
      name: "screens: an enabled line without its layer", processID: EmissionScreensProcess.id,
      layers: ["RGB", "Ha"],
      expected: [
        "oiiiEnabled": RowNote(reason: "the screen needs its line layer", subject: "[OIII]")
      ]
    ),
    Reasons(
      name: "screens: every layer present", processID: EmissionScreensProcess.id,
      layers: ["RGB", "Ha", "OIII", "SII"], expected: [:]),
    Reasons(
      name: "injection: a gain on a missing line", processID: LineInjectionProcess.id,
      values: ["siiGain": .number(1)], layers: ["RGB", "Ha", "OIII"],
      expected: ["siiGain": RowNote(reason: "the injection needs its line layer", subject: "[SII]")]
    ),
    Reasons(
      name: "injection: a gain with every share at 0 still notes the missing line",
      processID: LineInjectionProcess.id,
      values: [
        "siiGain": .number(1), "siiRed": .number(0), "siiGreen": .number(0),
        "siiBlue": .number(0),
      ], layers: ["RGB"],
      expected: ["siiGain": RowNote(reason: "the injection needs its line layer", subject: "[SII]")]
    ),
    Reasons(
      name: "combination: two slots short of two layers, every layer named",
      processID: ChannelCombinationProcess.id,
      values: ["rSource": .choice("Ha*OIII"), "lSource": .choice("L")], layers: ["RGB"],
      expected: [
        "rSource": RowNote(
          reason: "the slot needs a layer the stack lacks", subject: "Hα + [OIII]"),
        "lSource": RowNote(reason: "the slot needs a layer the stack lacks", subject: "L"),
      ]),
    Reasons(
      name: "combination: a slot reading a missing layer", processID: ChannelCombinationProcess.id,
      values: ["bSource": .choice("OIII")], layers: ["RGB", "Ha"],
      expected: [
        "bSource": RowNote(reason: "the slot needs a layer the stack lacks", subject: "[OIII]")
      ]),
  ]

  @Test("testUnavailableReasons_perParam", arguments: reasons)
  func testUnavailableReasons_perParam(row: Reasons) throws {
    let type = try #require(ProcessRegistry.standard().type(id: row.processID))
    var params = ParamSet(schema: type.schema)
    for (id, value) in row.values { try params.set(id, value) }
    #expect(type.unavailableReasons(params, layerIDs: row.layers) == row.expected)
    for note in row.expected.values {
      #expect(type.rowReasons.contains(note.reason), "the reason is a catalog key")
    }
  }

  @Test("unavailableOptions: a value naming an absent layer is greyed with why; none by default")
  func testUnavailableOptions_layers() throws {
    #expect(
      StretchProcess.unavailableOptions(ParamSet(schema: StretchProcess.schema), layerIDs: ["RGB"])
        .isEmpty)
    var params = ParamSet(schema: ChannelCombinationProcess.schema)
    #expect(ChannelCombinationProcess.unavailableOptions(params, layerIDs: ["RGB"]).isEmpty)
    try params.set("rSource", .choice("Ha"))
    try params.set("bSource", .choice("Ha*OIII"))
    #expect(
      ChannelCombinationProcess.unavailableOptions(params, layerIDs: ["RGB"]) == [
        "rSource": ["Ha": ChannelCombinationProcess.missingLayerReason],
        "bSource": ["Ha*OIII": ChannelCombinationProcess.missingLayerReason],
      ])
    #expect(
      ChannelCombinationProcess.unavailableOptions(params, layerIDs: ["RGB", "Ha", "OIII"]).isEmpty)
  }
}
