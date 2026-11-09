import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0187: the chain preview is a task's work — cancelled between two steps it renders no
/// further step and throws `CancellationError`, so a drag's next position never waits behind the
/// whole chain of the one before.
@Suite(
  "StudioSession — the chain preview stops when its task is cancelled",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized)
struct StudioSessionChainCancelTests {
  static func registry() throws -> ProcessRegistry {
    try ProcessRegistry([CountingGain.self, ChannelCombinationProcess.self])
  }

  static func session(_ name: String) throws -> StudioSession {
    let history = try History(
      directory: try ScratchDirectory.url.appendingPathComponent(name),
      original: StudioSessionChainTests.ramp())
    return try StudioSession(
      history: history, bundle: StudioSessionChainTests.bundle, registry: try registry(),
      device: try #require(MTLCreateSystemDefaultDevice()))
  }

  static func gain(_ gain: Double) throws -> ParamSet {
    var params = ParamSet(schema: CountingGain.schema)
    try params.set("gain", .number(gain))
    return params
  }

  @Test("testPreviewChain_StopsWhenCancelled", .scratchDirectory)
  func testPreviewChain_StopsWhenCancelled() async throws {
    let session = try Self.session("applied")
    for value in [1.5, 0.8, 1.2] {
      try session.apply(CountingGain.id, params: try Self.gain(value))
    }
    CountingGain.reset()
    // The first render of the chain cancels the task it runs in.
    CountingGain.cancelAt.withLock { $0 = 1 }
    defer { CountingGain.reset() }

    let params = try Self.gain(0.5)
    // The task's result is only whether the chain rendered to the end (an image is not Sendable).
    let chain = Task {
      _ = try await session.previewChain(from: 0, params: params)
      return true
    }

    await #expect(throws: CancellationError.self) { try await chain.value }
    #expect(CountingGain.renders.withLock { $0 } == 1, "nothing rendered after the cancel")
  }

  @Test("testPreviewChain_RendersEveryStepWhenNotCancelled", .scratchDirectory)
  func testPreviewChain_RendersEveryStepWhenNotCancelled() async throws {
    let session = try Self.session("applied")
    for value in [1.5, 0.8, 1.2] {
      try session.apply(CountingGain.id, params: try Self.gain(value))
    }
    CountingGain.reset()
    defer { CountingGain.reset() }

    let preview = try await session.previewChain(from: 0, params: try Self.gain(0.5))

    #expect(preview.stoppedBefore == nil)
    #expect(CountingGain.renders.withLock { $0 } == 3)
  }
}
