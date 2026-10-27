import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0140 in the Studio: no camera is chosen for the user — Apply waits with the reason, the
/// header's camera is offered and never taken, a mono camera runs Siril's mono SPCC.
@MainActor
@Suite(
  "Colour calibration without a camera — Apply waits, header offer, mono route",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct ColourCalibrationChoiceTests {
  static let monoLists = [
    "log: Mono Sensors", "log: ZWO ASI1600MM", "log: Running command: spcc_list",
    "log: Red Filters", "log: Baader R", "log: Running command: spcc_list",
    "log: Green Filters", "log: Baader G", "log: Running command: spcc_list",
    "log: Blue Filters", "log: Baader B", "log: Running command: spcc_list",
    "log: White References", "log: Average Spiral Galaxy",
  ]

  static func english(_ resource: LocalizedStringResource?) -> String? {
    resource.map { String(localized: $0) }
  }

  @Test("unset, Apply is refused with the name to choose; Siril never runs", .scratchDirectory)
  func testUnchosenRefused() async throws {
    let opened = try await ColourCalibrationProcessTests.open()
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    let steps = workspace.studio.steps.count
    workspace.choose(ColourCalibrationProcess.id)
    let en = Locale(identifier: "en")
    #expect(
      Self.english(workspace.unchosenRefusal(locale: en)) == "Choose “Sensor (SPCC)” first.")
    #expect(
      Self.english(workspace.unchosenRefusal(locale: Locale(identifier: "fr")))
        == "Choisissez d’abord « Capteur (SPCC) ».")
    #expect(await workspace.runTool() == false)
    #expect(workspace.failure == workspace.unchosenRefusal())
    #expect(workspace.studio.steps.count == steps && opened.siril.calls.isEmpty)
    let panel = try #require(workspace.panel)
    panel.set("sensor", .choice("Sony IMX571"))
    #expect(
      Self.english(workspace.unchosenRefusal(locale: en))
        == "Choose “Filter on the camera (SPCC)” first.")
    panel.set("method", .choice("pcc"))
    #expect(workspace.unchosenRefusal() == nil, "PCC needs no sensor")
  }

  @Test("the header's camera is offered on the sensor, never set", .scratchDirectory)
  func testHeaderCameraOffered() async throws {
    let header = FITSHeader(cards: [
      FITSHeader.Card(keyword: "INSTRUME", value: "'ZWO ASI2600MC Air'")
    ])
    let opened = try await ColourCalibrationProcessTests.open(header: header)
    defer { try? opened.project.package.close() }
    opened.workspace.choose(ColourCalibrationProcess.id)
    let panel = try #require(opened.workspace.panel)
    #expect(panel.suggestions == ColourCalibrationProcess.suggestions(header: header))
    #expect(panel.suggestions.map(\.paramID) == ["camera", "sensor"])
    #expect(panel.params.choice("sensor").isEmpty, "offered, not taken")
  }

  @Test("a mono camera asks for the mono names, then runs Siril's mono SPCC", .scratchDirectory)
  func testMonoRoute() async throws {
    let opened = try await ColourCalibrationProcessTests.open(lists: Self.monoLists)
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    workspace.choose(ColourCalibrationProcess.id)
    let panel = try #require(workspace.panel)
    panel.set("camera", .choice("mono"))
    #expect(
      Self.english(workspace.unchosenRefusal(locale: Locale(identifier: "en")))
        == "Choose “Mono sensor (SPCC)” first.")
    for (id, name) in [
      ("monoSensor", "ZWO ASI1600MM"), ("rFilter", "Baader R"), ("gFilter", "Baader G"),
      ("bFilter", "Baader B"),
    ] {
      panel.set(id, .choice(name))
    }
    #expect(workspace.unchosenRefusal() == nil)
    #expect(await workspace.runTool())
    let line: String =
      #"spcc "-monosensor=ZWO ASI1600MM" "-rfilter=Baader R" "-gfilter=Baader G""#
      + #" "-bfilter=Baader B" "-whiteref=Average Spiral Galaxy""#
    #expect(opened.siril.calls.last?.contains(line) == true, "\(opened.siril.calls)")
  }
}
