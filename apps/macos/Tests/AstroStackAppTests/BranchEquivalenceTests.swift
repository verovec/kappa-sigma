import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// The combined image after a branch step and Replay is the main history run over the stack with
/// that layer replaced by the branch head, bit for bit (card 0118's overlay contract).
@MainActor
@Suite(
  "Branch — replayed combined equals the chain over the branch head",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct BranchEquivalenceTests {
  @Test("testReplayEqualsChainOverHead", .scratchDirectory, arguments: ["RGB", "Ha"])
  func testReplayEqualsChainOverHead(layerID: String) async throws {
    let root = try ScratchDirectory.url
    var screens = ParamSet(schema: EmissionScreensProcess.schema)
    try screens.set("haOpacity", .number(0.6))
    let chain: (StudioModel) throws -> Void = { model in
      try model.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
      try model.apply(EmissionScreensProcess.id, params: screens)
    }

    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let model = try BranchTests.model(opened)
    try chain(model)
    let unbranched = model.head.planes
    try model.applyBranch(layerID, DenoiseProcess.id, params: BranchTests.denoise())
    #expect(model.staleFrom != nil)
    let workspace = try StudioWorkspaceModel(studio: model, base: [.color, .emission])
    try await StudioUndo.replayMain(workspace, on: UndoManager())
    #expect(model.staleFrom == nil)
    let head = try #require(model.session.branches.branch(layerID)?.head)

    var bundle = BranchTests.bundle()
    bundle.layers[layerID] = head
    bundle.layerStats[layerID] = StudioSession.stats(of: head)
    if layerID == "RGB" { bundle.stats = StudioSession.stats(of: head) }
    let package = try ProjectPackage.create(at: root.appendingPathComponent("Ref.astrostack"))
    defer { try? package.close() }
    let stack = try package.store.addStack(
      bundlePath: "stacks/ref", sourceIDs: [], paramsJSON: "{}",
      imageRoles: ["RGB", "Ha", "OIII"])
    let reference = try StudioModel(
      store: package.store, stackID: stack.id, packageFolder: package.url,
      stackFolder: package.url.appendingPathComponent("stacks/ref"), bundle: bundle)
    try chain(reference)

    #expect(StudioSession.samePixels(model.head.planes, reference.head.planes))
    #expect(!StudioSession.samePixels(model.head.planes, unbranched), "the branch reached it")
  }
}
