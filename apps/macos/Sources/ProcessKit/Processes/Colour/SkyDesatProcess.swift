package import Metal

/// Hue-aware sky desaturation on linear RGB: the sky's brown/olive mottle goes, the colour of
/// stars and of bright extended signal stays, and (keep-cool) a blue reflection veil too.
///
/// Card 0053, port of the legacy `chromasmooth.go` `sky_desat` passes (cards 0025–0027). The
/// masks are brightness-relative — fractions of the sky level, never stack-noise σ (in a deep
/// stack the faintest dust sits at 40–400σ, card 0026): a star is a local peak over the coarse
/// field, extended signal a large coarse lift, the floor a near-zero lift. Stage 1 pulls the
/// chroma toward its star-masked coarse field (the 10–100 px colour alternation goes, broad colour
/// stays); stage 2 greys the true floor. The pixel mean (R+G+B)/3 is preserved exactly.
///
/// R2: the sky level and the chroma σ come from the bundle statistics (mean of the channel
/// medians; mean MADN · √(2/3)), and every band is a parameter the panel shows.
package struct SkyDesatProcess: ImageProcess {
  package static let id = "sky-desat"
  package static let title = "Sky desaturation"
  package static let stage = ProcessStage.linear
  package static let previewExactOnlyAt1to1 = true

  package static let schema = ParamSchema(
    [
      ParamSpec(
        id: "strength", title: "Strength", unit: .opacity, level: .simple, number: 0, in: 0...1),
      ParamSpec(id: "keepCool", title: "Keep cool hues", level: .simple, flag: false),
      ParamSpec(
        id: "scalePx", title: "Coarse scale", unit: .px, level: .advanced, number: 48, in: 2...512),
      ParamSpec(
        id: "starDetailPx", title: "Star detail", unit: .px, level: .advanced, number: 2,
        in: 0...16),
      ParamSpec(
        id: "coreGuardPx", title: "Star-core guard", unit: .px, level: .advanced, number: 4,
        in: 0...8),
      ParamSpec(
        id: "coreLevel", title: "Star-core level", unit: .none, level: .advanced, number: 0.85,
        in: 0...1),
    ] + band("star", "Star", low: 0.005, high: 0.02)
      + band("nebula", "Bright signal", low: 0.02, high: 0.10)
      + band("floor", "Sky floor", low: 1e-4, high: 4e-4))

  /// The two ends of a brightness-relative band, as fractions of the sky level.
  private static func band(_ id: String, _ title: String, low: Double, high: Double) -> [ParamSpec]
  {
    [
      ParamSpec(
        id: id + "Low", title: title + " band start", unit: .none, level: .advanced, number: low,
        in: 0...1),
      ParamSpec(
        id: id + "High", title: title + " band end", unit: .none, level: .advanced, number: high,
        in: 0...1),
    ]
  }

  package let params: ParamSet
  private let pipelines: SkyDesatPipelines

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipelines = try SkyDesatPipelines(device: device)
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try ColourKernel.checkSizes(input, output)
    guard input.planes.count == 3, params.number("strength") > 0 else {
      return try ColourKernel.copy(input, into: output, commands: context.commands)
    }
    let uniforms = try SkyDesatUniforms(params: params, stats: stats, scale: context.scale)
    try pipelines.encode(input, into: output, uniforms: uniforms, commands: context.commands)
  }
}
