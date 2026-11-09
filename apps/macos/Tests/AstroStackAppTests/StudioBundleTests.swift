import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import StackKit
import TestSupport
import Testing

/// Card 0187: `StudioBundle.load` reads and measures the stack's layers side by side (hundreds of
/// MB apiece on a real stack) and hands back exactly what the one-by-one read gave: every layer,
/// its statistics, the roles and the base layer's header.
@MainActor
struct StudioBundleTests {
  @Test("testLoad_LayersMeasuredInParallelKeepOrderAndStats", .scratchDirectory)
  func testLoad_LayersMeasuredInParallelKeepOrderAndStats() async throws {
    let source = try LegacyRunSource(folder: try LegacyRunWindowTests.run(in: ScratchDirectory.url))
    #expect(source.layers.count == 3)

    let (bundle, roles, header) = try await StudioBundle.load(source)

    // The serial oracle: each layer read and measured in turn.
    var expectedStats: [String: LayerStats] = [:]
    for layer in source.layers {
      let image = try FITSFile.read(at: source.url(of: layer)).image()
      expectedStats[layer.id] = LayerStats.measured(image)
      #expect(bundle.layers[layer.id]?.planes == image.planes, "layer \(layer.id)")
    }
    #expect(Set(bundle.layers.keys) == Set(source.layers.map(\.id)))
    #expect(bundle.layerStats == expectedStats)
    #expect(bundle.stats == expectedStats["RGB"], "the base layer's statistics")
    #expect(roles == [.color, .emission])
    #expect(header != nil, "the base layer's header")
  }
}
