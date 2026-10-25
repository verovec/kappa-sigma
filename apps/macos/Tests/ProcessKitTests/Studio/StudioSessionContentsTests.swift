import ProcessKit
import Testing

/// What the combined image holds (card 0131): the base layer until a step reads another; a
/// channel combination replaces the set with its sources, any other step adds what it reads.
@Suite("StudioSession — the bundle layers the combined image holds")
struct StudioSessionContentsTests {
  /// One row: the main steps (process id, values set on its schema), the bundle's layers and the
  /// layers the head holds.
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let steps: [(String, [String: ParamValue])]
    var layerIDs: Set<String> = ["RGB", "Ha", "OIII"]
    let holds: Set<String>
    var testDescription: String { name }
  }

  static let broadband: [String: ParamValue] = [:]
  static let hoo: [String: ParamValue] = [
    "rSource": .choice("Ha"), "gSource": .choice("OIII"), "bSource": .choice("OIII"),
  ]

  static let cases = [
    Case(name: "empty history: the base layer", steps: [], holds: ["RGB"]),
    Case(
      name: "broadband combination", steps: [(ChannelCombinationProcess.id, broadband)],
      holds: ["RGB"]),
    Case(
      name: "Hα injected after the calibration",
      steps: [
        (ChannelCombinationProcess.id, broadband), (ColourCalibrationProcess.id, [:]),
        (LineInjectionProcess.id, ["haGain": .number(1)]),
      ], holds: ["RGB", "Ha"]),
    Case(
      name: "gains 0 inject nothing",
      steps: [(ChannelCombinationProcess.id, broadband), (LineInjectionProcess.id, [:])],
      holds: ["RGB"]),
    Case(
      name: "HOO combination drops the broadband",
      steps: [(ChannelCombinationProcess.id, hoo)], holds: ["Ha", "OIII"]),
    Case(
      name: "a later combination replaces what came before",
      steps: [
        (ChannelCombinationProcess.id, broadband),
        (LineInjectionProcess.id, ["oiiiGain": .number(1)]), (ChannelCombinationProcess.id, hoo),
      ], holds: ["Ha", "OIII"]),
    // Read is not merged: a layer rewritten beside the head, or a continuum subtracted.
    Case(
      name: "background extraction of the lines alone",
      steps: [
        (ChannelCombinationProcess.id, broadband),
        (BackgroundExtractionProcess.id, ["applyTo": .choice("lines")]),
      ], holds: ["RGB"]),
    Case(
      name: "a continuum subtracted from a HOO palette adds no broadband",
      steps: [
        (ChannelCombinationProcess.id, hoo),
        (LineInjectionProcess.id, ["haGain": .number(1), "haContinuumK": .number(0.2)]),
      ], holds: ["Ha", "OIII"]),
    Case(
      name: "emission screens lay their enabled lines in, not their continuum",
      steps: [
        (ChannelCombinationProcess.id, broadband),
        (
          EmissionScreensProcess.id,
          [
            "haEnabled": .flag(false), "oiiiEnabled": .flag(true), "oiiiContinuum": .flag(true),
          ]
        ),
      ], holds: ["RGB", "OIII"]),
    // A slot or a screen that adds nothing merges nothing.
    Case(
      name: "a slot at weight 0 and an L at opacity 0",
      steps: [
        (
          ChannelCombinationProcess.id,
          [
            "bSource": .choice("OIII"), "bWeight": .number(0), "lSource": .choice("Ha"),
            "lOpacity": .number(0),
          ]
        )
      ], holds: ["RGB"]),
    Case(
      name: "an enabled screen at opacity 0",
      steps: [
        (ChannelCombinationProcess.id, broadband),
        (
          EmissionScreensProcess.id,
          ["haEnabled": .flag(false), "oiiiEnabled": .flag(true), "oiiiOpacity": .number(0)]
        ),
      ], holds: ["RGB"]),
    Case(
      name: "single-layer bundle", steps: [(ChannelCombinationProcess.id, broadband)],
      layerIDs: ["RGB"], holds: ["RGB"]),
  ]

  @Test("testCombinedLayers", arguments: cases)
  func testCombinedLayers(row: Case) throws {
    let registry = try ProcessRegistry.standard()
    let steps = try row.steps.map { id, values in
      let type = try #require(registry.type(id: id))
      var params = ParamSet(schema: type.schema)
      for (key, value) in values { try params.set(key, value) }
      return (processID: id, params: params)
    }

    let holds = StudioSession.combinedLayers(
      after: steps, layerIDs: row.layerIDs, registry: registry)

    #expect(holds == row.holds)
  }
}
