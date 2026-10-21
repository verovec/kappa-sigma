import Foundation
import ImageKit
import Metal
import ProcessKit
import RenderKit
import Synchronization
import TestSupport
import Testing

/// The runner's inputs: the bundle a locked step needs, the breakpoint Continue needs, the
/// statistics each step gets.
extension PipelineRunnerTests {
  @Test("a locked step re-runs when the bundle it ran against differs", .scratchDirectory)
  func testLockedStepNeedsTheSameBundle() async throws {
    let recorded = Pipeline(name: "M31", steps: [try Self.gain(2), try Self.gain(3, locked: true)])
    let runner = try Self.runner()
    let first = try History(directory: try Self.folder("a"), original: Self.image(0.1))
    _ = try await runner.run(recorded, on: first, bundle: Self.bundle)
    var restacked = Self.bundle
    restacked.layers = ["Ha": Self.image(0.05)]
    let log = EventLog()
    _ = try await runner.replay(
      recorded, on: Self.image(0.1), in: try Self.folder("b"), bundle: restacked,
      previous: PipelineRun(history: first, bundle: Self.bundle), onEvent: log.sink)
    #expect(log.events == [.applied(0), .applied(1)])
  }

  @Test(
    "Continue is refused when the history no longer stands at the breakpoint", .scratchDirectory)
  func testResumeRefusedAfterUndo() async throws {
    let pipeline = Pipeline(name: "M31", steps: [try Self.gain(2), try Self.gain(3, .stop)])
    let history = try History(directory: try Self.folder("h"), original: Self.image(0.1))
    let runner = try Self.runner()
    _ = try await runner.run(pipeline, on: history, bundle: Self.bundle)
    try history.undo()
    await #expect(throws: PipelineError.notAtBreakpoint(step: 1, steps: 0)) {
      _ = try await runner.resume(pipeline, at: 1, on: history, bundle: Self.bundle)
    }
    await #expect(throws: PipelineError.notAtBreakpoint(step: 0, steps: 0)) {
      _ = try await runner.resume(pipeline, at: 0, on: history, bundle: Self.bundle)
    }
  }

  @Test(
    "a later step gets the statistics of the image it receives, not the bundle's", .scratchDirectory
  )
  func testLaterStepsGetTheirInputStats() async throws {
    let ramp = AstroImage(
      width: 64, height: 2, planes: [(0..<128).map { 0.02 + 0.2 * Float($0 % 64) / 63 }],
      metadata: ImageMetadata(rowOrder: .topDown))
    var stretch = ParamSet(schema: StretchProcess.schema)
    try stretch.set("mode", .choice("mtf"))
    let pipeline = Pipeline(
      name: "M31", steps: [try Self.gain(2), Self.step(StretchProcess.id, stretch)])
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try await Self.runner().replay(
      pipeline, on: ramp, in: try Self.folder("h"), bundle: Self.bundle)
    // The same stretch applied by hand to the gained image, with that image's statistics.
    let gained = try result.history.output(ofStep: 0)
    let stats = LayerStats(
      channels: gained.planes.map { plane in
        let (median, madn) = AutoSTF.medianAndMADN(plane)
        return ChannelStats(
          median: median, madn: madn, minimum: Double(plane.min() ?? 0),
          maximum: Double(plane.max() ?? 0))
      })
    let byHand = try ProcessRunner(device: device).run(
      StretchProcess(params: stretch, device: device),
      input: GPUImage(device: device, image: gained), stats: stats
    ).read()
    #expect(result.history.current.planes == byHand)
  }
}

/// `PipelineBundle.isSameInput`: what a locked step's reuse compares.
@Suite("Pipeline bundle — same input")
struct PipelineBundleTests {
  static func image(_ value: Float, rows: RowOrder = .topDown) -> AstroImage {
    AstroImage(
      width: 2, height: 1, planes: [[value, value]], metadata: ImageMetadata(rowOrder: rows))
  }

  @Test("same stats and identical layers are the same input; any difference is not")
  func testSameInput() {
    let stats = LayerStats(channels: [ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1)]
    )
    let base = PipelineBundle(
      stats: stats, layers: ["Ha": Self.image(0.2)], layerStats: ["Ha": stats])
    #expect(base.isSameInput(as: base))
    var other = base
    other.layers = ["Ha": Self.image(0.3)]
    #expect(!base.isSameInput(as: other), "other pixels")
    other.layers = ["Ha": Self.image(0.2, rows: .bottomUp)]
    #expect(!base.isSameInput(as: other), "other metadata")
    other.layers = ["OIII": Self.image(0.2)]
    #expect(!base.isSameInput(as: other), "other layers")
    other = base
    other.layerStats = [:]
    #expect(!base.isSameInput(as: other), "other layer stats")
    other = base
    other.stats = LayerStats(channels: [])
    #expect(!base.isSameInput(as: other), "other stats")
  }
}
