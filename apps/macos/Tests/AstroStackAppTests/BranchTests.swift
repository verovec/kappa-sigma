import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// Studio branches (card 0118): one history per bundle layer, its head overlaying that layer for
/// the main history, refused for anything that is not a per-layer linear process, reopened as it
/// was and mirrored on the layer's own `images` row.
@MainActor
@Suite(
  "Branch — per-layer history, head overlay, refusals, reopen",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct BranchTests {
  static let size = 8

  /// A fake BB + DB stack: an RGB layer of three ramps and two line layers of one plane each.
  static func bundle() -> PipelineBundle {
    let count = size * size
    func ramp(_ offset: Int, _ scale: Float) -> [Float] {
      (0..<count).map { Float(($0 * 5 + offset) % count) / Float(count) * scale + 0.02 }
    }
    let metadata = ImageMetadata(rowOrder: .topDown)
    let rgb = AstroImage(
      width: size, height: size, planes: [ramp(0, 0.3), ramp(3, 0.25), ramp(9, 0.2)],
      metadata: metadata)
    let layers = [
      "RGB": rgb,
      "Ha": AstroImage(width: size, height: size, planes: [ramp(11, 0.4)], metadata: metadata),
      "OIII": AstroImage(width: size, height: size, planes: [ramp(17, 0.2)], metadata: metadata),
    ]
    return PipelineBundle(
      stats: StudioSession.stats(of: rgb), layers: layers,
      layerStats: layers.mapValues(StudioSession.stats(of:)))
  }

  static func project() throws -> StudioModelTests.Opened {
    let root = try ScratchDirectory.url
    let package = try ProjectPackage.create(at: root.appendingPathComponent("M31.astrostack"))
    let stack = try package.store.addStack(
      bundlePath: "stacks/run1", sourceIDs: [], paramsJSON: "{}",
      imageRoles: ["RGB", "Ha", "OIII"])
    return StudioModelTests.Opened(
      package: package, stackID: stack.id,
      folder: package.url.appendingPathComponent("stacks/run1"))
  }

  static func model(_ opened: StudioModelTests.Opened) throws -> StudioModel {
    try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: bundle())
  }

  /// A denoise that changes the pixels (the schema's amount is 0: the identity).
  static func denoise() throws -> ParamSet {
    var params = ParamSet(schema: DenoiseProcess.schema)
    try params.set("amount", .number(1))
    try params.set("noise", .number(0.05))
    return params
  }

  @Test("testHeadOverlaysItsLayer", .scratchDirectory, arguments: ["RGB", "Ha", "OIII"])
  func testHeadOverlaysItsLayer(layerID: String) throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try Self.model(opened)
    let base = Self.bundle()

    try model.applyBranch(layerID, DenoiseProcess.id, params: Self.denoise())

    let branch = try #require(model.session.branches.branch(layerID))
    #expect(branch.history.steps.map(\.processID) == [DenoiseProcess.id])
    let head = branch.history.current
    #expect(head.planes != base.layers[layerID]?.planes, "the denoise changed the layer")
    // The main history reads the head under the layer's id, the other layers as stacked.
    #expect(model.session.bundle.layers[layerID]?.planes == head.planes)
    for (id, layer) in base.layers where id != layerID {
      #expect(model.session.bundle.layers[id]?.planes == layer.planes, "\(id) unchanged")
    }
    let stats = try model.session.layerStats()
    #expect(stats[layerID] == LayerStats.measured(head).keepingFit(of: base.layerStats[layerID]))
  }

  @Test(
    "testRefusesGeometryAndNonBranchable", .scratchDirectory,
    arguments: [
      ("cropLeft", GeometryProcess.id, StudioError.BranchRefusal.movesPixels),
      ("rotation", GeometryProcess.id, .movesPixels),
      ("", StretchProcess.id, .notPerLayer),
      ("", ColourBalanceProcess.id, .needsColour),
    ])
  func testRefusesGeometryAndNonBranchable(
    param: String, processID: String, reason: StudioError.BranchRefusal
  ) throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try Self.model(opened)
    let schema = try #require(model.session.registry.type(id: processID)).schema
    var params = ParamSet(schema: schema)
    if param == "cropLeft" { try params.set(param, .number(2)) }
    if param == "rotation" { try params.set(param, .choice("90")) }

    #expect(throws: StudioError.notBranchable(processID: processID, reason: reason)) {
      try model.applyBranch("Ha", processID, params: params)
    }
    #expect(model.session.branches.branch("Ha")?.history.steps.isEmpty ?? true)
    #expect(model.session.bundle.layers["Ha"]?.planes == Self.bundle().layers["Ha"]?.planes)
  }

  @Test("testReopenRoundTrip", .scratchDirectory)
  func testReopenRoundTrip() throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try Self.model(opened)
    try model.applyBranch("Ha", DenoiseProcess.id, params: Self.denoise())
    let head = try #require(model.session.branches.branch("Ha")).history.current

    let reopened = try Self.model(opened)
    let branch = try #require(reopened.session.branches.branch("Ha"))
    #expect(branch.history.steps.map(\.processID) == [DenoiseProcess.id])
    #expect(branch.history.steps.first?.params == (try Self.denoise()))
    #expect(branch.history.current.planes == head.planes)
    #expect(reopened.session.bundle.layers["Ha"]?.planes == head.planes)
    // Mirrored on the layer's own row (added by `addStack`), never on the `studio` one.
    let store = opened.package.store
    let image = try #require(try store.images(stackID: opened.stackID).first { $0.role == "Ha" })
    let rows = try store.history(imageID: image.id)
    #expect(rows.map(\.processID) == [DenoiseProcess.id])
    #expect(image.headStepID == rows.last?.id)
    try reopened.undoBranch("Ha")
    #expect(reopened.session.bundle.layers["Ha"]?.planes == Self.bundle().layers["Ha"]?.planes)
    let undone = try #require(try store.images(stackID: opened.stackID).first { $0.role == "Ha" })
    #expect(undone.headStepID == nil, "undo moved the mirrored head back to the layer")
    try reopened.redoBranch("Ha")
    #expect(reopened.session.bundle.layers["Ha"]?.planes == head.planes)
  }
}
