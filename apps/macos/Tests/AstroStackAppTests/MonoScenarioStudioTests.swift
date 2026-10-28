import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import TestSupport
import Testing

/// Card 0142: the Studio opened on the bundle each synthetic scenario stacks into — the base
/// layer, the switcher, the palette the first combination takes, what « Combined » says, and
/// colour calibration waiting for the sensor (none is ever guessed for a synthetic rig).
@MainActor
@Suite(
  "Mono scenarios in the Studio — base layer, switcher, palette, contents, SPCC",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct MonoScenarioStudioTests {
  struct Expected: Sendable {
    /// The bundle a real Siril run writes: layer id → planes.
    let planes: [String: Int]
    let selections: [String]
    /// The first combination's R, G, B, L sources.
    let sources: [String]
    let contents: String?
  }

  static let expected: [SyntheticCapture.Scenario: Expected] = [
    .lrgbHa: Expected(
      planes: ["L": 1, "R": 1, "G": 1, "B": 1, "Ha": 1],
      selections: ["main", "L", "R", "G", "B", "Ha"], sources: ["R", "G", "B", "L"],
      contents:
        "Holds Luminance + Red + Green + Blue; not yet Hydrogen-alpha (to add with Line "
        + "injection or Emission screens)."),
    .sho: Expected(
      planes: ["Ha": 1, "OIII": 1, "SII": 1], selections: ["main", "Ha", "OIII", "SII"],
      sources: ["SII", "Ha", "OIII", "none"],
      contents: "Holds Hydrogen-alpha + Oxygen III + Sulphur II."),
    .lOnly: Expected(
      planes: ["L": 1], selections: [], sources: ["L", "L", "L", "none"], contents: nil),
    .oscSIIOIII: Expected(
      planes: ["RGB": 3, "OIII": 1, "SII": 1], selections: ["main", "RGB", "OIII", "SII"],
      sources: ["RGB.r", "RGB.g", "RGB.b", "none"],
      contents:
        "Holds Broadband (RGB); not yet Oxygen III or Sulphur II (to add with Line injection "
        + "or Emission screens)."),
  ]

  /// A bundle of `planes`: a ramp per plane, every layer on one grid.
  static func bundle(_ planes: [String: Int]) -> PipelineBundle {
    let size = StudioModelTests.size
    var layers: [String: AstroImage] = [:]
    for (id, count) in planes {
      let values = (0..<count).map { plane in
        (0..<(size * size)).map { Float($0 + plane * 5) / Float(size * size * 4) + 0.01 }
      }
      layers[id] = AstroImage(
        width: size, height: size, planes: values, metadata: ImageMetadata(rowOrder: .topDown))
    }
    let stats = layers.mapValues { StudioSession.stats(of: $0) }
    let base = StudioSession.baseLayerID(planes.keys) ?? ""
    let first = stats[base] ?? stats.values.first ?? LayerStats(channels: [])
    return PipelineBundle(stats: first, layers: layers, layerStats: stats)
  }

  static func workspace(_ scenario: SyntheticCapture.Scenario) throws
    -> (StudioWorkspaceModel, StudioModelTests.Opened)
  {
    let expected = try #require(Self.expected[scenario])
    let opened = try StudioModelTests.project()
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: Self.bundle(expected.planes))
    let base: Set<LayerRole> = expected.planes.keys.contains("RGB") ? [.color] : []
    return (try StudioWorkspaceModel(studio: studio, base: base), opened)
  }

  @Test(
    "testStudio: base layer first in the switcher, the palette its layers spell, what it holds",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testStudio(scenario: SyntheticCapture.Scenario) throws {
    let expected = try #require(Self.expected[scenario])
    let (workspace, opened) = try Self.workspace(scenario)
    defer { try? opened.package.close() }
    #expect(workspace.selections.map { $0.layerID ?? "main" } == expected.selections)
    let step = try #require(workspace.studio.steps.first)
    #expect(step.processID == ChannelCombinationProcess.id)
    #expect(ChannelCombinationProcess.slotSources.map(step.params.choice) == expected.sources)
    let words = workspace.combinedContents.map {
      String(localized: $0.words(locale: Locale(identifier: "en")))
    }
    #expect(words == expected.contents)
    if scenario == .lrgbHa {
      let french = workspace.combinedContents.map {
        String(localized: $0.words(locale: Locale(identifier: "fr")))
      }
      #expect(
        french?.hasPrefix("Contient Luminance + Rouge + Vert + Bleu") == true, "\(french ?? "")")
    }
  }

  @Test(
    "testSPCCRefusedUntilChosen: a synthetic rig suggests no sensor; Apply waits for one",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testSPCCRefusedUntilChosen(scenario: SyntheticCapture.Scenario) throws {
    let instrument = scenario.isColour ? "Synthetic OSC" : "Synthetic Mono"
    let header = FITSHeader(cards: [
      FITSHeader.Card(keyword: "INSTRUME", value: "'\(instrument)'")
    ])
    #expect(ColourCalibrationProcess.suggestions(header: header).isEmpty)
    var params = ParamSet(schema: ColourCalibrationProcess.schema)
    if !scenario.isColour { try params.set("camera", .choice("mono")) }
    let names =
      scenario.isColour
      ? ColourCalibrationProcess.oscNames : ColourCalibrationProcess.monoNames
    #expect(ColourCalibrationProcess.unchosen(params) == names)
  }

  @Test("testSPCCMonoArguments: a mono camera's names reach Siril's mono SPCC line")
  func testSPCCMonoArguments() throws {
    var params = ParamSet(schema: ColourCalibrationProcess.schema)
    for (id, value) in [
      ("camera", "mono"), ("monoSensor", "Sony IMX411/455/461/533/571"),
      ("rFilter", "Astronomik Deep Sky RGB Red"), ("gFilter", "Astronomik Deep Sky RGB Green"),
      ("bFilter", "Astronomik Deep Sky RGB Blue"),
    ] {
      try params.set(id, .choice(value))
    }
    #expect(ColourCalibrationProcess.unchosen(params).isEmpty)
    let line = ColourCalibrationTool.request(params).command.line
    #expect(line.hasPrefix(#"spcc "-monosensor=Sony IMX411/455/461/533/571""#))
    #expect(line.contains(#""-rfilter=Astronomik Deep Sky RGB Red""#))
    #expect(line.contains(#""-bfilter=Astronomik Deep Sky RGB Blue""#))
  }
}
