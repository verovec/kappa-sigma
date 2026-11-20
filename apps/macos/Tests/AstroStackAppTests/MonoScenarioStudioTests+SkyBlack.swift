import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import StackKit
import TestSupport
import Testing

/// Card 0172: re-editing the first combination offers each slot's black point under its layer's
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

  /// A bundle of `planes` where every plane has its own sky under a faint ramp: a slot offered
  /// another layer's sky, or a cropped layer's, shows.
  static func skyBundle(_ planes: [String: Int]) -> PipelineBundle {
    let size = StudioModelTests.size
    var layers: [String: AstroImage] = [:]
    for (index, id) in planes.keys.sorted().enumerated() {
      let values = (0..<(planes[id] ?? 1)).map { plane in
        (0..<(size * size)).map { pixel in
          Float(index + 1) * 0.05 + Float(plane) * 0.01 + Float(pixel % size) / 4000
        }
      }
      layers[id] = AstroImage(
        width: size, height: size, planes: values, metadata: ImageMetadata(rowOrder: .topDown))
    }
    let stats = layers.mapValues { StudioSession.stats(of: $0) }
    let base = StudioSession.baseLayerID(planes.keys) ?? ""
    return PipelineBundle(
      stats: stats[base] ?? LayerStats(channels: []), layers: layers, layerStats: stats)
  }

  /// The black suggestions of the panel now open.
  static func blacks(_ workspace: StudioWorkspaceModel) throws -> [Suggestion] {
    try #require(workspace.panel).suggestions.filter { $0.paramID.hasSuffix("Black") }
  }

  @Test(
    "testSkyBlacksOffered: editing step 0 offers its own layers' skies, shown, and sets none",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testSkyBlacksOffered(scenario: SyntheticCapture.Scenario) throws {
    let ids = try #require(Self.blacksOffered[scenario])
    let planes = try #require(Self.expected[scenario]).planes
    let bundle = Self.skyBundle(planes)
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: bundle)
    let base = Set(planes.keys.map { StudioBundle.role(of: LinearBundle.Role(filter: $0)) })
    let workspace = try StudioWorkspaceModel(studio: studio, base: base)
    let recorded = try #require(workspace.studio.steps.first).params
    let stack = ChannelCombinationProcess.blackSuggestions(recorded, layers: bundle.layerStats)
    #expect(stack.map(\.paramID) == ids)
    for (one, next) in zip(stack, stack.dropFirst()) { #expect(one.value != next.value) }

    workspace.editStep(0)
    #expect(try Self.blacks(workspace) == stack)
    let panel = try #require(workspace.panel)
    #expect(!panel.showsAdvanced)
    #expect(Set(ids).isSubset(of: Set(panel.visibleSpecs.map(\.id))), "an offered row is shown")
    #expect(panel.params == recorded, "offered, not set")
    workspace.cancelEdit()

    // A crop moves every layer: step 0 is still offered the skies of what it read.
    var crop = ParamSet(schema: GeometryProcess.schema)
    try crop.set("cropLeft", .number(2))
    workspace.choose(GeometryProcess.id, params: crop)
    try workspace.apply()
    workspace.editStep(0)
    #expect(workspace.failure == nil)
    #expect(try Self.blacks(workspace) == stack)
    #expect(try #require(workspace.studio.steps.first).params == recorded)

    // Another process chosen during that edit is on the head: offered the head's statistics.
    workspace.choose(ChannelCombinationProcess.id, params: recorded)
    #expect(workspace.editing == nil)
    let head = ChannelCombinationProcess.blackSuggestions(
      recorded, layers: try workspace.studio.session.layerStats())
    #expect(try Self.blacks(workspace) == head)
    #expect(ids.isEmpty || head != stack, "the cropped layers have another sky")
  }

  @Test("testBlacksTakenStayShown: on a mono head too, a black the step subtracts is on screen")
  func testBlacksTakenStayShown() throws {
    let params = try ChannelCombinationProcess.initialParams(planes: ["R": 1, "G": 1, "B": 1])
    let panel = ProcessPanelModel(type: ChannelCombinationProcess.self, params: params)
    panel.headStats = LayerStats(
      channels: [ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1)])
    #expect(!panel.visibleSpecs.map(\.id).contains("gBlack"))
    panel.set("gBlack", .number(0.0086))
    #expect(panel.visibleSpecs.map(\.id).contains("gBlack"))
    #expect(!panel.visibleSpecs.map(\.id).contains("rBlack"))
  }
}
