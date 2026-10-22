import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import Testing

extension StudioModelTests {
  /// Every layer a registered process can read, at the stack's size: RGB, the three lines and a
  /// starless (as a StarNet step would have written).
  static func fullBundle() -> PipelineBundle {
    let count = size * size
    func layer(_ planes: Int, _ offset: Int) -> AstroImage {
      AstroImage(
        width: size, height: size,
        planes: (0..<planes).map { plane in
          (0..<count).map { Float(($0 + offset + plane * 5) % count) / Float(count * 3) + 0.02 }
        },
        metadata: ImageMetadata(rowOrder: .topDown))
    }
    let layers = [
      "RGB": layer(3, 0), "Ha": layer(1, 11), "OIII": layer(1, 23), "SII": layer(1, 37),
      "starless": layer(3, 5),
    ]
    let stats = layers.mapValues(StudioSession.stats(of:))
    let base = StudioSession.stats(of: layers["RGB"] ?? layer(3, 0))
    return PipelineBundle(stats: base, layers: layers, layerStats: stats)
  }

  /// Card 0087 (the 0049 contract through the model): the preview at scale 1 and the applied
  /// head are the same pixels, for every process of the standard registry.
  @Test("testPreviewEqualsApply", .scratchDirectory, arguments: try ProcessRegistry.standard().ids)
  func testPreviewEqualsApply(processID: String) throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder,
      bundle: Self.fullBundle())
    let type = try #require(try ProcessRegistry.standard().type(id: processID))
    let params = ParamSet(schema: type.schema)
    let preview = try model.preview(processID, params: params)
    // A host tool's step is its tool's (0093): the GPU render, the image itself, is refused.
    if type.hostTool {
      #expect(preview.planes == model.head.planes, "\(processID): the preview is the image")
      #expect(throws: StudioError.needsTool(processID)) {
        try model.apply(processID, params: params)
      }
      return
    }
    try model.apply(processID, params: params)
    #expect(model.head.planes == preview.planes, "\(processID)")
  }
}
