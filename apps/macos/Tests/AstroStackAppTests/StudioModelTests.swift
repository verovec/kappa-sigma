import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// The Studio's working image (card 0087): a history per stack whose step 0 is the channel
/// combination, mirrored in ProjectKit, applied / undone / redone, reopened as it was.
@MainActor
@Suite(
  "StudioModel — step 0, apply / undo / redo, reopen, step outputs",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioModelTests {
  static let size = 8

  /// A fake stack: an RGB layer of three ramps, as a bundle would hand it to the Studio.
  static func bundle() -> PipelineBundle {
    let count = size * size
    let planes = (0..<3).map { channel in
      (0..<count).map { Float($0 + channel * 7) / Float(count * 4) + 0.01 }
    }
    let rgb = AstroImage(
      width: size, height: size, planes: planes, metadata: ImageMetadata(rowOrder: .topDown))
    let stats = StudioSession.stats(of: rgb)
    return PipelineBundle(stats: stats, layers: ["RGB": rgb], layerStats: ["RGB": stats])
  }

  struct Opened {
    let package: ProjectPackage
    let stackID: Int64
    let folder: URL
  }

  static func project() throws -> Opened {
    let root = try ScratchDirectory.url
    let package = try ProjectPackage.create(at: root.appendingPathComponent("M31.astrostack"))
    let stack = try package.store.addStack(
      bundlePath: "stacks/run1", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB"])
    return Opened(
      package: package, stackID: stack.id,
      folder: package.url.appendingPathComponent("stacks/run1"))
  }

  static func model(_ opened: Opened) throws -> StudioModel {
    try StudioModel(
      store: opened.package.store, stackID: opened.stackID, stackFolder: opened.folder,
      bundle: bundle())
  }

  @Test("testOpenCreatesCombinationStepAndHead", .scratchDirectory)
  func testOpenCreatesCombinationStepAndHead() throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try Self.model(opened)

    #expect(model.steps.map(\.processID) == ["channel-combination"])
    // The head is exactly what ProcessRunner makes of the bundle with the defaults.
    let expected = try model.session.render(
      ChannelCombinationProcess.id,
      params: ParamSet(schema: ChannelCombinationProcess.schema))
    #expect(model.head.planes == expected.planes)
    let store = opened.package.store
    let image = try #require(
      try store.images(stackID: opened.stackID).first { $0.role == "studio" })
    let rows = try store.history(imageID: image.id)
    #expect(rows.map(\.processID) == ["channel-combination"])
    #expect(image.headStepID == rows.last?.id)
  }

  @Test("testApplyUndoRedoSurviveReopen", .scratchDirectory)
  func testApplyUndoRedoSurviveReopen() throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try Self.model(opened)
    let combined = model.head.planes

    try model.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    let stretched = model.head.planes
    #expect(stretched != combined)
    try model.undo()
    #expect(model.head.planes == combined)
    try model.redo()
    #expect(model.head.planes == stretched)
    let summary = try opened.package.store.summary().historySteps

    let reopened = try Self.model(opened)
    #expect(reopened.steps.map(\.processID) == ["channel-combination", "stretch"])
    #expect(reopened.head.planes == stretched)
    #expect(try opened.package.store.summary().historySteps == summary)
    try reopened.undo()
    #expect(reopened.head.planes == combined)
    let image = try #require(
      try opened.package.store.images(stackID: opened.stackID).first { $0.role == "studio" })
    let rows = try opened.package.store.history(imageID: image.id)
    #expect(image.headStepID == rows.first?.id, "undo moved the mirrored head back")
  }

  @Test("testStepOutputsOverlayLayers", .scratchDirectory)
  func testStepOutputsOverlayLayers() throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try Self.model(opened)
    #expect(model.session.layerIDs().contains("starless") == false)

    let starless = AstroImage(
      width: Self.size, height: Self.size,
      planes: Array(repeating: Array(repeating: 0.05, count: Self.size * Self.size), count: 3),
      metadata: ImageMetadata(rowOrder: .topDown))
    try model.apply(
      "stars-split", params: ParamSet(schema: ParamSchema([])), result: model.head,
      outputs: [.starless: starless])
    #expect(model.session.layerIDs().contains("starless"))
    // The next step's context reads the overlay: star recomposition runs on it.
    _ = try model.session.render(
      StarRecompositionProcess.id, params: ParamSet(schema: StarRecompositionProcess.schema))
    try model.undo()
    #expect(model.session.layerIDs().contains("starless") == false)
  }
}

extension StudioModelTests {
  /// The rows follow the history whatever fails: an apply that throws after an undo leaves the
  /// undone step redoable, and the rows still one per kept step with the head on the last one.
  @Test("a failed apply after an undo keeps the history and its rows in step", .scratchDirectory)
  func testFailedApplyKeepsRowsInStep() throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try Self.model(opened)
    try model.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    try model.undo()
    #expect(throws: StudioError.unknownProcess("nope")) {
      try model.apply("nope", params: ParamSet(schema: ParamSchema([])))
    }
    try model.redo()
    let store = opened.package.store
    let image = try #require(
      try store.images(stackID: opened.stackID).first { $0.role == "studio" })
    let rows = try store.history(imageID: image.id)
    #expect(rows.map(\.processID) == ["channel-combination", "stretch"])
    #expect(image.headStepID == rows.last?.id)
  }
}
