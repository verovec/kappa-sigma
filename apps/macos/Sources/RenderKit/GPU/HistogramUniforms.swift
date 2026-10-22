/// Swift mirror of `HistogramUniforms` in `Shaders/ShaderTypes.h` — the header is the
/// definition; `ShaderLayoutProbe` pins this layout to what the GPU compiles.
struct HistogramUniforms {
  /// STF c0 per channel (display domain).
  var shadows: SIMD4<Float>
  /// STF m per channel.
  var midtone: SIMD4<Float>
  /// STF c1 per channel.
  var highlights: SIMD4<Float>
  /// 1 or 3.
  var channels: UInt32
  /// Sample every `stride` pixels in x and y.
  var stride: UInt32
  /// First sampled column.
  var originX: UInt32
  /// First sampled row.
  var originY: UInt32
  /// Region width in pixels.
  var width: UInt32
  /// Region height in pixels.
  var height: UInt32
  /// 1: bins of the displayed values (after the STF), 0: the linear values.
  var stfEnabled: UInt32

  /// Counts `area` of a `channels`-plane image every `stride` pixels, through `stf` when given.
  init(channels: Int, stride: Int, area: PixelRegion, stf: [STFParameters]?) {
    let lanes = STFLanes(stf)
    shadows = lanes.shadows
    midtone = lanes.midtone
    highlights = lanes.highlights
    self.channels = UInt32(channels)
    self.stride = UInt32(stride)
    originX = UInt32(area.x)
    originY = UInt32(area.y)
    width = UInt32(area.width)
    height = UInt32(area.height)
    stfEnabled = lanes.enabled
  }
}
