import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

/// Card 0172: re-editing the first combination offers each slot's black point at its layer's
/// sky, through the panel every suggestion goes through; nothing is set until the user says so.
extension MonoScenarioStudioTests {
  /// The black parameters the panel of step 0 is offered, per scenario: one per slot reading a
  /// mono master, none on a colour bundle nor on the grey of a single layer.
  static let blacksOffered: [SyntheticCapture.Scenario: [String]] = [
    .lrgbHa: ["rBlack", "gBlack", "bBlack", "lBlack"],
    .sho: ["rBlack", "gBlack", "bBlack"],
    .lOnly: [],
    .oscSIIOIII: [],
    .oscDualband: [],
  ]

  @Test(
    "testSkyBlacksOffered: editing step 0 offers the layers' medians, and applies none (R2)",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testSkyBlacksOffered(scenario: SyntheticCapture.Scenario) throws {
    let ids = try #require(Self.blacksOffered[scenario])
    let (workspace, opened) = try Self.workspace(scenario)
    defer { try? opened.package.close() }
    let recorded = try #require(workspace.studio.steps.first).params
    workspace.editStep(0)
    let panel = try #require(workspace.panel)
    let offered = panel.suggestions.filter { $0.paramID.hasSuffix("Black") }
    #expect(offered.map(\.paramID) == ids)
    let stats = try workspace.studio.session.layerStats()
    for suggestion in offered {
      let slot = String(suggestion.paramID.dropLast("Black".count)) + "Source"
      let sky = LayerPlane(recorded.choice(slot)).stats(in: stats)?.median
      #expect(suggestion.value == sky.map(ParamValue.number))
      #expect(suggestion.reason == ChannelCombinationProcess.skyBlackReason)
      #expect(panel.params.number(suggestion.paramID) == 0, "offered, not set")
    }
    #expect(panel.params == recorded)
    #expect(try #require(workspace.studio.steps.first).params == recorded)
  }
}
