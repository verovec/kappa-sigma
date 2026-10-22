import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import StackKit
import TestSupport
import Testing

extension StudioToolsTests {
  /// The installed-tools tool over a machine without GraXpert: a GraXpert request fails with
  /// GraXpert's own error, nothing else runs (R2).
  @Test("the live tool names a missing GraXpert, never another engine", .scratchDirectory)
  func testLiveMissingGraXpert() async throws {
    let tool = BackgroundExtractionTool.live(
      scratch: try ScratchDirectory.url.appendingPathComponent("bge"),
      hostTools: HostTools { .missing(path: "/nowhere/\($0.productName)") })
    await #expect(throws: GraXpertError.missing(path: "/nowhere/GraXpert")) {
      let image = AstroImage(
        width: 2, height: 2, planes: [[0.1, 0.2, 0.3, 0.4]],
        metadata: ImageMetadata(rowOrder: .topDown))
      _ = try await tool.step(
        PipelineRunner.BatchInput(image: image, layers: [:]),
        ParamSet(schema: BackgroundExtractionProcess.schema)
      ) { _ in }
    }
  }
}
