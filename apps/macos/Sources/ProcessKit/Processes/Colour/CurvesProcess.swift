package import Metal

/// PixInsight-style curves on stretched data: a monotone spline per curve (RGB, R, G, B,
/// luminance, saturation), sampled into a 1024-entry LUT the shader interpolates.
///
/// Card 0053. Applied in that order: the RGB curve on every channel, each channel's own, the
/// luminance curve as a lift of every channel by f(Y) − Y (Rec. 709, the colour differences
/// kept), then the saturation curve on HSL S. An identity curve is skipped, so the defaults are
/// the identity bit for bit. A mono image takes the RGB and luminance curves only.
package struct CurvesProcess: ImageProcess {
  package static let id = "curves"
  package static let title = "Curves"
  package static let stage = ProcessStage.nonlinear
  package static let previewExactOnlyAt1to1 = false
  /// Samples per curve in the LUT texture.
  package static let lutSize = 1024
  /// Control points a curve may hold.
  package static let maxPoints = 16
  /// The curves, in the order the kernel applies them (one LUT row each).
  package static let curves = ["rgb", "red", "green", "blue", "luminance", "saturation"]
  private static let identity = [CurvePoint(0, 0), CurvePoint(1, 1)]

  package static let schema = ParamSchema(
    zip(curves, ["RGB", "Red", "Green", "Blue", "Luminance", "Saturation"]).map { id, title in
      ParamSpec(
        id: id, title: title, level: .simple, points: identity, maxCount: maxPoints)
    })

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState
  private let table: MTLTexture
  private let active: [Float]

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ColourKernel.pipeline(device: device, function: "curves")
    let rows = Self.curves.map { params.points($0) }
    active = rows.map { $0 == Self.identity || $0.isEmpty ? 0 : 1 }
    let values = rows.flatMap { points in
      points.count < 2 ? MonotoneSpline(Self.identity).lut() : MonotoneSpline(points).lut()
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r32Float, width: Self.lutSize, height: Self.curves.count, mipmapped: false)
    descriptor.usage = .shaderRead
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw ProcessError.commandFailed("curves LUT texture")
    }
    values.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { return }
      unsafe texture.replace(
        region: MTLRegionMake2D(0, 0, Self.lutSize, Self.curves.count), mipmapLevel: 0,
        withBytes: base, bytesPerRow: Self.lutSize * MemoryLayout<Float>.stride)
    }
    table = texture
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try ColourKernel.checkSizes(input, output)
    // p[0] planes · p[1 + row] 1 when the row's curve is not the identity
    try ColourKernel.encode(
      pipeline, input, into: output, values: [Float(input.planes.count)] + active,
      extra: [table], commands: context.commands)
  }
}
