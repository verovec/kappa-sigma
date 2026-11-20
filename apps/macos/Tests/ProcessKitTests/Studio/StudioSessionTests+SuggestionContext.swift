import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0172: an applied step being edited is offered values from what THAT step reads — the
/// layers before it — not from the head the later steps left.
@Suite(
  "StudioSession — the suggestions of an edited step read its own inputs",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct StudioSessionSuggestionContextTests {
  /// A mono stack: three masters with their own sky, each a ramp no crop leaves alike.
  static var bundle: PipelineBundle {
    var layers: [String: AstroImage] = [:]
    for (id, sky) in zip(["R", "G", "B"], [Float(0.6), 0.4, 0.8]) {
      layers[id] = AstroImage(
        width: 4, height: 2, planes: [(0..<8).map { sky + Float($0 * $0) / 640 }],
        metadata: ImageMetadata(rowOrder: .topDown))
    }
    let stats = layers.mapValues { StudioSession.stats(of: $0) }
    return PipelineBundle(
      stats: stats["R"] ?? LayerStats(channels: []), layers: layers, layerStats: stats)
  }

  static func session(_ name: String) throws -> StudioSession {
    let history = try History(
      directory: try ScratchDirectory.url.appendingPathComponent(name),
      original: try #require(bundle.layers["R"]))
    return try StudioSession(
      history: history, bundle: bundle, registry: try StudioSessionChainTests.registry(),
      device: try #require(MTLCreateSystemDefaultDevice()))
  }

  /// The blacks the combination is offered from `stats`, by parameter.
  static func blacks(_ params: ParamSet, _ stats: [String: LayerStats]) -> [Suggestion] {
    ChannelCombinationProcess.blackSuggestions(params, layers: stats)
  }

  @Test("testSuggestions_BeforeAnEditedStep", .scratchDirectory)
  func testSuggestions_BeforeAnEditedStep() async throws {
    let session = try Self.session("edited")
    let combination = try ChannelCombinationProcess.initialParams(planes: ["R": 1, "G": 1, "B": 1])
    let type = ChannelCombinationProcess.self
    let stack = Self.blacks(combination, session.bundle.layerStats)
    #expect(stack.map(\.paramID) == ["rBlack", "gBlack", "bBlack"])
    #expect(try session.suggestions(for: type, params: combination) == stack, "no step: the stack")

    // A crop moves every layer: the head's layers are no longer the ones step 0 read.
    try session.apply(type.id, params: combination)
    let crop = try StudioSessionChainTests.crop()
    try session.apply(crop.id, params: crop.params)
    let gain = try StudioSessionChainTests.gain(1.5)
    try session.apply(gain.id, params: gain.params)
    let head = Self.blacks(combination, try session.layerStats())
    #expect(head != stack, "the cropped layers have another sky")
    #expect(try session.suggestions(for: type, params: combination) == head, "next step: the head")

    #expect(
      try session.suggestions(for: type, params: combination, before: 0) == stack,
      "step 0 read the stack's layers")
    #expect(
      try session.suggestions(for: type, params: combination, before: 1) == stack,
      "the crop read them too")
    let afterCrop = try session.suggestions(for: type, params: combination, before: 2)
    #expect(afterCrop == head, "the gain read the cropped layers")

    // The same once the chain preview of that edit holds its input.
    _ = try await session.previewChain(from: 2, params: gain.params)
    #expect(try session.suggestions(for: type, params: combination, before: 2) == afterCrop)
    #expect(
      try session.suggestions(for: type, params: combination, before: 9) == head,
      "no such step: the head")
  }
}
