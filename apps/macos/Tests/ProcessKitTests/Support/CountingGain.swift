import Metal
import ProcessKit
import Synchronization

/// `DummyGain` that counts its renders and, at a chosen one, cancels the task rendering it: how a
/// chain preview is caught mid-chain (card 0187). The counters are shared by every instance: a
/// test reads and resets them around its own chain.
struct CountingGain: ImageProcess {
  static let id = "counting-gain"
  static let title = "Counting gain"
  static let stage = ProcessStage.any
  static let schema = GainKernel.schema
  static let previewExactOnlyAt1to1 = true
  /// Renders so far, every instance counted.
  static let renders = Mutex(0)
  /// The render (1-based) that cancels the current task; `nil`: none does.
  static let cancelAt = Mutex<Int?>(nil)
  let params: ParamSet
  private let pipeline: MTLComputePipelineState

  init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try GainKernel.pipeline(device: device)
  }

  func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    let count = Self.renders.withLock { renders in
      renders += 1
      return renders
    }
    if Self.cancelAt.withLock({ $0 }) == count {
      withUnsafeCurrentTask { $0?.cancel() }
    }
    try GainKernel.encode(
      pipeline, gain: params.number("gain"), shiftPx: 0, input: input, output: output,
      context: context)
  }

  /// Counters back to nothing counted, nothing cancelling.
  static func reset() {
    renders.withLock { $0 = 0 }
    cancelAt.withLock { $0 = nil }
  }
}
