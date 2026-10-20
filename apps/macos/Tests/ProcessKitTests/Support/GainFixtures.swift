import Metal
import ProcessKit

/// `DummyGain`: output(x, y) = gain · input(x − shift / scale, y), edge-clamped — the smallest
/// process with a number and a `.px` parameter. The misbehaving variants each break one contract.
enum GainKernel {
  static let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void dummyGain(texture2d<float, access::read> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant float2 &p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
      if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
      int shift = int(round(p.y));
      int x = clamp(int(gid.x) - shift, 0, int(src.get_width()) - 1);
      dst.write(src.read(uint2(uint(x), gid.y)) * p.x, gid);
    }
    """

  static func pipeline(device: MTLDevice) throws -> MTLComputePipelineState {
    try ProcessLibrary.pipeline(device: device, source: source, function: "dummyGain")
  }

  /// Encodes gain and the effective shift (in working pixels) over every plane.
  static func encode(
    _ pipeline: MTLComputePipelineState, gain: Double, shiftPx: Double,
    input: GPUImage, output: GPUImage, context: RenderContext
  ) throws {
    var values = SIMD2(Float(gain), Float(shiftPx))
    for (source, target) in zip(input.planes, output.planes) {
      guard let encoder = context.commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("dummyGain encoder")
      }
      encoder.setComputePipelineState(pipeline)
      encoder.setTexture(source, index: 0)
      encoder.setTexture(target, index: 1)
      encoder.setBytes(&values, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
      encoder.dispatchThreads(
        MTLSize(width: output.width, height: output.height, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
      encoder.endEncoding()
    }
  }

  static let schema = ParamSchema([
    ParamSpec(id: "gain", title: "Gain", unit: .none, level: .simple, number: 1, in: 0...8),
    ParamSpec(id: "shift", title: "Shift", unit: .px, level: .advanced, number: 0, in: 0...16),
  ])
}

/// The well-behaved fixture: passes every contract.
struct DummyGain: ImageProcess {
  static let id = "dummy-gain"
  static let title = "Dummy gain"
  static let stage = ProcessStage.any
  static let schema = GainKernel.schema
  static let previewExactOnlyAt1to1 = true
  let params: ParamSet
  private let pipeline: MTLComputePipelineState

  init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try GainKernel.pipeline(device: device)
  }

  func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try GainKernel.encode(
      pipeline, gain: params.number("gain"), shiftPx: params.number("shift") / context.scale,
      input: input, output: output, context: context)
  }

  func suggestions(stats: LayerStats) -> [Suggestion] {
    // A suggestion from the bundle statistics only (R2: shown, never applied by itself).
    guard let median = stats.channels.first?.median, median > 0 else { return [] }
    return [
      Suggestion(
        paramID: "gain", value: .number(0.25 / median), reason: "brings the median to 0.25")
    ]
  }
}

/// Keeps a counter across renders: fails NoHiddenState.
final class HiddenStateGain: ImageProcess {
  static let id = "hidden-state-gain"
  static let title = "Hidden state"
  static let stage = ProcessStage.any
  static let schema = GainKernel.schema
  static let previewExactOnlyAt1to1 = true
  let params: ParamSet
  private let pipeline: MTLComputePipelineState
  private var renders = 0

  init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try GainKernel.pipeline(device: device)
  }

  func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    renders += 1
    try GainKernel.encode(
      pipeline, gain: params.number("gain") * Double(renders), shiftPx: 0, input: input,
      output: output, context: context)
  }
}

/// Renders a slightly different image for the preview: fails PreviewEqualsApply.
struct PreviewDriftGain: ImageProcess {
  static let id = "preview-drift-gain"
  static let title = "Preview drift"
  static let stage = ProcessStage.any
  static let schema = GainKernel.schema
  static let previewExactOnlyAt1to1 = true
  let params: ParamSet
  private let pipeline: MTLComputePipelineState

  init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try GainKernel.pipeline(device: device)
  }

  func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    let drift = context.purpose == .preview ? 0.01 : 0
    try GainKernel.encode(
      pipeline, gain: params.number("gain") + drift, shiftPx: 0, input: input, output: output,
      context: context)
  }
}

/// Reads its `.px` parameter as working pixels at every scale: fails PxUnitsScale.
struct ScaleBlindGain: ImageProcess {
  static let id = "scale-blind-gain"
  static let title = "Scale blind"
  static let stage = ProcessStage.any
  static let schema = GainKernel.schema
  static let previewExactOnlyAt1to1 = true
  let params: ParamSet
  private let pipeline: MTLComputePipelineState

  init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try GainKernel.pipeline(device: device)
  }

  func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try GainKernel.encode(
      pipeline, gain: params.number("gain"), shiftPx: params.number("shift"), input: input,
      output: output, context: context)
  }
}
