import AstroStackApp
import Foundation
import Metal
import ProcessKit
import StackKit
import TestSupport
import Testing

/// Card 0171: a mono stack whose step 0 was recorded as a grey reopens with the palette its
/// layers spell offered on the combination panel — one click, and nothing written before it.
@MainActor
@Suite(
  "Studio combination — the spelled palette offered on a grey step 0, never applied",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioCombinationSuggestionTests {
  static let grey = ["L", "L", "L", "none"]

  /// The Studio of `planes`, its step 0 recorded with `sources` (the opening ones when nil).
  static func workspace(planes: [String: Int], sources: [String]?) throws
    -> (StudioWorkspaceModel, StudioModelTests.Opened)
  {
    let opened = try StudioModelTests.project()
    var combination: ParamSet?
    if let sources {
      var params = ParamSet(schema: ChannelCombinationProcess.schema)
      try ChannelCombinationProcess.set(sources: sources, on: &params)
      combination = params
    }
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: MonoScenarioStudioTests.bundle(planes),
      combination: combination)
    let base = Set(planes.keys.map { StudioBundle.role(of: LinearBundle.Role(filter: $0)) })
    return (try StudioWorkspaceModel(studio: studio, base: base), opened)
  }

  @Test(
    "a grey step 0 on LRGB + Hα layers: LRGB offered in one click, in fr and en",
    .scratchDirectory)
  func testGreyStepZero_OffersThePalette() throws {
    let planes = ["L": 1, "R": 1, "G": 1, "B": 1, "Ha": 1]
    let (workspace, opened) = try Self.workspace(planes: planes, sources: Self.grey)
    defer { try? opened.package.close() }
    workspace.editStep(0)
    let panel = try #require(workspace.panel)
    let reason = ChannelCombinationProcess.spelledReason
    #expect(panel.suggestions.map(\.paramID) == ChannelCombinationProcess.slotSources)
    #expect(panel.suggestions.map(\.value) == ["R", "G", "B", "L"].map { .choice($0) })
    #expect(panel.groupedReasons == [reason])
    #expect(
      ProcessPanelModel.words(
        reason: reason, subject: panel.subject(of: reason), locale: Locale(identifier: "fr"))
        == "les couches épellent une palette que cette étape ne lit pas (LRGB)")
    #expect(
      ProcessPanelModel.words(
        reason: reason, subject: panel.subject(of: reason), locale: Locale(identifier: "en"))
        == "the layers spell a palette this step does not read (LRGB)")

    // Asked, shown, not applied: the panel and the recorded step still hold the grey (R2).
    #expect(ChannelCombinationProcess.slotSources.map(panel.params.choice) == Self.grey)
    let recorded = try #require(workspace.studio.steps.first)
    #expect(ChannelCombinationProcess.slotSources.map(recorded.params.choice) == Self.grey)

    // The user's click fills the panel; the history moves only on « Apply the edit ».
    panel.take(reason: reason)
    #expect(Palette.matching(panel.params) == .lrgb)
    let still = try #require(workspace.studio.steps.first)
    #expect(ChannelCombinationProcess.slotSources.map(still.params.choice) == Self.grey)
  }

  @Test(
    "the step 0 a stack opens on is offered nothing: OSC and mono panels are unchanged",
    .scratchDirectory,
    arguments: [
      ["RGB": 3], ["RGB": 3, "Ha": 1, "OIII": 1], ["L": 1, "R": 1, "G": 1, "B": 1, "Ha": 1],
      ["Ha": 1, "OIII": 1, "SII": 1], ["L": 1],
    ])
  func testOpeningStepZero_OffersNothing(planes: [String: Int]) throws {
    let (workspace, opened) = try Self.workspace(planes: planes, sources: nil)
    defer { try? opened.package.close() }
    workspace.editStep(0)
    #expect(try #require(workspace.panel).suggestions.isEmpty)
  }
}
