import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Cards 0161 / 0188: what a slider drag on a revised step costs per frame — `previewChain` on a
/// 22 Mpx colour image through a 7-step GPU chain, from the first, a middle and the last step.
///
/// Optimised builds only, local (`Live`: skipped by `just test-unit`, never on CI); the table is
/// printed for card 0161's record, the budget pins the GPU-resident chain (0188).
@Suite(
  "Live chain latency — 7 GPU steps at 22 Mpx",
  .enabled(
    if: BuildConfiguration.optimized
      && ProcessInfo.processInfo.environment["ASTROSTACK_SKIP_LIVE"] != "1"),
  .tags(.live), .serialized, .timeLimit(.minutes(10)))
struct LiveChainLatencyTests {
  static let steps = [
    StretchProcess.id, HDRProcess.id, ColourBalanceProcess.id, CurvesProcess.id,
    SaturationProcess.id, DenoiseProcess.id, SkyDesatProcess.id,
  ]

  /// A 6248 × 4176 colour image of low-amplitude noise around 0.05: the processes' cost depends
  /// on the size, not the content.
  static func image() -> AstroImage {
    let (width, height) = (6248, 4176)
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next() -> Float {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Float(seed >> 40) / Float(1 << 24) * 0.02 + 0.05
    }
    let planes = (0..<3).map { _ in (0..<(width * height)).map { _ in next() } }
    return AstroImage(
      width: width, height: height, planes: planes, metadata: ImageMetadata(rowOrder: .topDown))
  }

  @Test("previewChain from the first, a middle and the last step", .scratchDirectory)
  func testPreviewChain_22MpxWithinBudget() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let image = Self.image()
    let stats = StudioSession.stats(of: image)
    let bundle = PipelineBundle(stats: stats, layers: ["RGB": image], layerStats: ["RGB": stats])
    let history = try History(
      directory: try ScratchDirectory.url.appendingPathComponent("latency"), original: image)
    let registry = try ProcessRegistry.standard()
    let session = try StudioSession(
      history: history, bundle: bundle, registry: registry, device: device)
    for id in Self.steps {
      let type = try #require(registry.type(id: id))
      try session.apply(id, params: ParamSet(schema: type.schema))
    }
    let clock = ContinuousClock()
    var table: [String] = []
    var bestFromFirst = Duration.zero
    for k in [0, 3, 6] {
      let type = try #require(registry.type(id: Self.steps[k]))
      let params = ParamSet(schema: type.schema)
      // The first render uploads the chain's input; the next three are a drag's frames.
      _ = try await session.previewChain(from: k, params: params)
      var frames: [Duration] = []
      for _ in 0..<3 {
        frames.append(
          try await clock.measure { _ = try await session.previewChain(from: k, params: params) })
      }
      if k == 0 { bestFromFirst = frames.min() ?? .zero }
      let measured = frames.map { "\($0)" }.joined(separator: ", ")
      table.append("k=\(k) steps=\(Self.steps.count - k): \(measured)")
    }
    // Card 0161's record; printed. The budget reads the best frame: the chain's capability, not
    // the Mac's load at that second (a flaky budget is worse than none).
    print("LiveChainLatencyTests (0188, GPU-resident chain):\n" + table.joined(separator: "\n"))
    #expect(bestFromFirst < .milliseconds(500), "7 steps from k = 0: \(bestFromFirst)")
  }
}
