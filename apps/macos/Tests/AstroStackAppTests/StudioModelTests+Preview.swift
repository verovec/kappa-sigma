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
  /// head are the same pixels, for every GPU process of the standard registry (a batch process's
  /// preview is its result, design §4.6: `BackgroundExtractionProcessTests`).
  @Test(
    "testPreviewEqualsApply", .scratchDirectory,
    arguments: try ProcessRegistry.standard().types.filter { !$0.isBatch }.map { $0.id })
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
    try model.apply(processID, params: params)
    #expect(model.head.planes == preview.planes, "\(processID)")
  }
}
