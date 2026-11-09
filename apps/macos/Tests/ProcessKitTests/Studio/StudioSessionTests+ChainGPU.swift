import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0188: the chain preview stays on the GPU — its input measured there, its steps and
/// moved layers textures — and gives the pixels the revise's replay writes.
@Suite(
  "StudioSession — the chain preview on the GPU equals the replay",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct StudioSessionChainGPUTests {
  typealias Chain = StudioSessionChainTests

  /// From a middle step: the chain's input is a step's output, measured on the GPU.
  @Test("testPreviewChain_FromAMiddleStepEqualsReplay", .scratchDirectory)
  func testPreviewChain_FromAMiddleStepEqualsReplay() async throws {
    let session = try Chain.session("applied")
    try Chain.applying(
      [try Chain.gain(1.5), try Chain.stretch(0.2), try Chain.gain(0.8)], on: session)

    let preview = try await session.previewChain(from: 1, params: try Chain.stretch(0.35).params)

    let expected = try await Chain.replayed(
      [try Chain.gain(1.5), try Chain.stretch(0.35), try Chain.gain(0.8)], "scratch")
    #expect(preview.stoppedBefore == nil)
    #expect(Chain.same(preview.image, expected), "bit-identical to the revise's replay")
  }

  /// A crop moves every context layer: the moved layers stay on the GPU too.
  @Test("testPreviewChain_MovedLayersStayOnTheGPU", .scratchDirectory)
  func testPreviewChain_MovedLayersStayOnTheGPU() async throws {
    let session = try Chain.session("applied")
    try Chain.applying([try Chain.gain(1.5), try Chain.crop(), Chain.combination], on: session)

    let preview = try await session.previewChain(from: 0, params: try Chain.gain(0.5).params)

    #expect(preview.image.width == 3, "the combination read the RGB layer the crop moved")
    let expected = try await Chain.replayed(
      [try Chain.gain(0.5), try Chain.crop(), Chain.combination], "scratch")
    #expect(Chain.same(preview.image, expected))
  }
}
