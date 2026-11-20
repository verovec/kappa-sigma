import AstroStackApp
import Foundation
import ProcessKit
import StackKit
import Testing

/// Card 0194: a kept profile's combination never makes a step 0 the stack cannot render, and
/// the slots it lost are said on the combination panel.
extension StudioModelTests {
  static func combination(_ sources: [String]) throws -> ParamSet {
    var params = ParamSet(schema: ChannelCombinationProcess.schema)
    try ChannelCombinationProcess.set(sources: sources, on: &params)
    return params
  }

  static func workspace(planes: [String: Int], profile: [String]) throws
    -> (StudioWorkspaceModel, Opened)
  {
    let opened = try Self.project()
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: MonoScenarioStudioTests.bundle(planes),
      combination: try combination(profile))
    let base = Set(planes.keys.map { StudioBundle.role(of: LinearBundle.Role(filter: $0)) })
    return (try StudioWorkspaceModel(studio: studio, base: base), opened)
  }

  @Test(
    "testStepZero_ProfileWithAbsentLayers: an LRGB profile on L + Hα opens on layers it holds",
    .scratchDirectory)
  func testStepZero_ProfileWithAbsentLayers() throws {
    let planes = ["L": 1, "Ha": 1]
    let (workspace, opened) = try Self.workspace(planes: planes, profile: ["R", "G", "B", "L"])
    defer { try? opened.package.close() }
    let step = try #require(workspace.studio.steps.first)
    #expect(step.processID == ChannelCombinationProcess.id)
    #expect(ChannelCombinationProcess.slotSources.map(step.params.choice) == ["L", "L", "L", "L"])
    #expect(
      ChannelCombinationProcess.unavailableReasons(step.params, layerIDs: Set(planes.keys)).isEmpty)
  }

  @Test(
    "each replaced row of the combination panel names what the profile asked for, in fr and en",
    .scratchDirectory)
  func testStepZero_ReplacedRowsAreSaid() throws {
    let (workspace, opened) = try Self.workspace(
      planes: ["L": 1, "Ha": 1], profile: ["R", "G", "B", "L"])
    defer { try? opened.package.close() }
    workspace.editStep(0)
    let panel = try #require(workspace.panel)
    let reason = ChannelCombinationProcess.profileReason
    #expect(Set(panel.rowNotes.keys) == ["rSource", "gSource", "bSource"])
    #expect(panel.rowNotes["rSource"] == RowNote(reason: reason, subject: "R"))
    #expect(
      ProcessPanelModel.words(reason: reason, subject: "R", locale: Locale(identifier: "fr"))
        == "le profil demande une couche que l’empilement n’a pas (R)")
    #expect(
      ProcessPanelModel.words(reason: reason, subject: "R", locale: Locale(identifier: "en"))
        == "the profile asks for a layer the stack lacks (R)")
    // Another panel gets none of it.
    workspace.choose(LevelsProcess.id)
    #expect(try #require(workspace.panel).rowNotes.isEmpty)
  }

  @Test("the pipeline column runs the fitted combination, not the profile's lost sources")
  func testFittedPipeline() throws {
    let lrgb = Recipe(
      processID: ChannelCombinationProcess.id, params: try Self.combination(["R", "G", "B", "L"]))
    let levels = Recipe(processID: LevelsProcess.id, params: ParamSet(schema: LevelsProcess.schema))
    let profile = Pipeline(
      name: "galaxy-mono-lrgb-ha",
      steps: [PipelineStep(recipe: lrgb), PipelineStep(recipe: levels, mode: .stop)])

    // Undo step 0 then Run replays the column: it must hold sources the stack has.
    let fitted = try ProjectWindowModel.fitted(profile, planes: ["L": 1, "Ha": 1])
    let params = ParamSet.loading(
      fitted.steps[0].recipe.params, onto: ChannelCombinationProcess.schema
    ).params
    #expect(ChannelCombinationProcess.slotSources.map(params.choice) == ["L", "L", "L", "L"])
    #expect(fitted.name == profile.name)
    #expect(Array(fitted.steps.dropFirst()) == Array(profile.steps.dropFirst()))

    // Every source present: the profile's pipeline as it is.
    let whole = ["L": 1, "R": 1, "G": 1, "B": 1, "Ha": 1]
    #expect(try ProjectWindowModel.fitted(profile, planes: whole) == profile)
  }

  @Test(
    "a profile whose sources all exist is step 0 as it is, with no note",
    .scratchDirectory,
    arguments: [
      (["RGB": 3], ["RGB.r", "RGB.g", "RGB.b", "none"]),
      (["L": 1, "R": 1, "G": 1, "B": 1, "Ha": 1], ["R", "G", "B", "L"]),
      (["L": 1, "R": 1, "G": 1, "B": 1, "Ha": 1], ["L", "L", "L", "none"]),
    ])
  func testStepZero_ProfileKept(planes: [String: Int], profile: [String]) throws {
    let (workspace, opened) = try Self.workspace(planes: planes, profile: profile)
    defer { try? opened.package.close() }
    let step = try #require(workspace.studio.steps.first)
    #expect(step.params == (try Self.combination(profile)))
    workspace.editStep(0)
    #expect(try #require(workspace.panel).rowNotes.isEmpty)
  }

  @Test(
    "testStepZero_ProfilePlaneTokenOnMonoLayer: an OSC dual-band profile opens a mono stack",
    .scratchDirectory)
  func testStepZero_ProfilePlaneTokenOnMonoLayer() throws {
    let planes = ["Ha": 1, "OIII": 1]
    let (workspace, opened) = try Self.workspace(
      planes: planes, profile: ["Ha.r", "Ha.g", "Ha.b", "none"])
    defer { try? opened.package.close() }
    let step = try #require(workspace.studio.steps.first)
    #expect(
      ChannelCombinationProcess.slotSources.map(step.params.choice)
        == ["Ha", "OIII", "OIII", "none"])
    workspace.editStep(0)
    let panel = try #require(workspace.panel)
    #expect(Set(panel.rowNotes.keys) == ["rSource", "gSource", "bSource"])
    let reason = ChannelCombinationProcess.profilePlaneReason
    #expect(panel.rowNotes["rSource"]?.reason == reason)
    #expect(
      ProcessPanelModel.words(reason: reason, subject: "Ha", locale: Locale(identifier: "fr"))
        == "le profil demande un plan couleur d’une couche qui n’en a pas (Ha)")
  }

  @Test(
    "a slot set to a colour plane of a one-plane layer says why it cannot run, in fr and en",
    .scratchDirectory)
  func testPanel_PlaneTokenOnMonoLayer() throws {
    let (workspace, opened) = try Self.workspace(
      planes: ["Ha": 1, "OIII": 1], profile: ["Ha", "OIII", "OIII", "none"])
    defer { try? opened.package.close() }
    workspace.choose(
      ChannelCombinationProcess.id, params: try Self.combination(["Ha.r", "OIII", "OIII", "none"]))
    let panel = try #require(workspace.panel)
    let reason = ChannelCombinationProcess.planeReason
    let note = try #require(panel.rowNotes["rSource"])
    #expect(note.reason == reason)
    #expect(Set(panel.rowNotes.keys) == ["rSource"])
    #expect(
      ProcessPanelModel.words(reason: reason, subject: "Ha", locale: Locale(identifier: "fr"))
        == "le canal lit un plan couleur d’une couche qui n’en a pas (Ha)")
    #expect(
      ProcessPanelModel.words(reason: reason, subject: "Ha", locale: Locale(identifier: "en"))
        == "the slot reads a colour plane of a layer that has none (Ha)")
  }
}
