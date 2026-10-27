import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import Testing

/// Step 0 follows the bundle (card 0138): the schema's defaults on a colour stack (its history
/// bytes unchanged — `StudioModelBranchTests.recordedManifestSHA256` holds), the palette the
/// layers spell otherwise.
extension StudioModelTests {
  /// A fake LRGB stack: four one-plane layers.
  static func lrgbBundle() -> PipelineBundle {
    let count = size * size
    let metadata = ImageMetadata(rowOrder: .topDown)
    var layers: [String: AstroImage] = [:]
    for (index, id) in ["L", "R", "G", "B"].enumerated() {
      let plane = (0..<count).map { Float($0 + index * 5) / Float(count * 4) + 0.01 }
      layers[id] = AstroImage(width: size, height: size, planes: [plane], metadata: metadata)
    }
    let luminance = layers["L"].map(StudioSession.stats(of:))
    return PipelineBundle(
      stats: luminance ?? LayerStats(channels: []), layers: layers,
      layerStats: layers.mapValues(StudioSession.stats(of:)))
  }

  enum Stack: String, Sendable { case osc, lrgb }

  struct StepZero: CustomTestStringConvertible, Sendable {
    let name: String
    let stack: Stack
    let sources: [String]
    var testDescription: String { name }
  }

  nonisolated static let stepZeros: [StepZero] = [
    StepZero(
      name: "OSC: the schema's defaults", stack: .osc,
      sources: ["RGB.r", "RGB.g", "RGB.b", "none"]),
    StepZero(name: "LRGB: the lrgb palette", stack: .lrgb, sources: ["R", "G", "B", "L"]),
  ]

  @Test("testStepZeroUsesInitialParams", .scratchDirectory, arguments: stepZeros)
  func testStepZeroUsesInitialParams(row: StepZero) throws {
    let opened = try Self.project()
    defer { try? opened.package.close() }
    let model = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: row.stack == .osc ? Self.bundle() : Self.lrgbBundle())
    let step = try #require(model.steps.first)
    #expect(step.processID == ChannelCombinationProcess.id)
    #expect(ChannelCombinationProcess.slotSources.map { step.params.choice($0) } == row.sources)
    if row.sources[0] == "RGB.r" {
      #expect(step.params == ParamSet(schema: ChannelCombinationProcess.schema))
    }
  }
}
