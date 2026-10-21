package import Metal

/// Puts the stars back on the starless image with their colour and presence chosen: the PO's
/// `stardesat` step after StarNet (design §4.4; Siril has no CLI star recomposition).
///
/// The input is the image with stars; the bundle layer `starless` is StarNet's output of it. The
/// star layer `max(original − starless, 0)` keeps its Rec. 709 luma and `chroma` × its colour
/// (0: grey stars, 1: the original colour; red giants otherwise render as orange blobs), and is
/// added back at `presence` (stardesat), or screened (PixInsight), clamped to [0, 1].
///
/// stardesat's semantics are kept on purpose: the star layer is clamped at 0, so where StarNet
/// brightened a pixel the starless wins (legacy `BlendStars` without the clamp was rejected).
package struct StarRecompositionProcess: ImageProcess {
  package static let id = "star-recomposition"
  package static let title = "Star layer"
  package static let stage = ProcessStage.nonlinear
  package static let requires: [LayerRole] = [.starless]
  package static let previewExactOnlyAt1to1 = false
  /// The recomposition modes, in panel order.
  package static let modes = ["additive", "screen"]
  /// The bundle layer the process reads the starless image from.
  package static let starlessLayer = "starless"

  package static let schema = ParamSchema([
    ParamSpec(
      id: "presence", title: "Star presence", unit: .opacity, level: .simple, number: 1, in: 0...1),
    ParamSpec(
      id: "chroma", title: "Star colour", unit: .none, level: .simple, number: 1, in: 0...1),
    ParamSpec(id: "mode", title: "Recomposition", level: .advanced, choice: "additive", of: modes),
  ])

  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "star colour 0.25: red giants otherwise render as orange blobs (the validated M31 chain)"
  ]

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ProcessLibrary.pipeline(
      device: device, file: "StarLayer.metal", function: "starLayer")
  }

  /// The PO's star colour (`stardesat 0.25`); never applied by the process.
  package func suggestions(stats: LayerStats) -> [Suggestion] {
    [Suggestion(paramID: "chroma", value: .number(0.25), reason: Self.suggestionReasons[0])]
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    guard input.planes.count == 3, output.planes.count == 3, output.width == input.width,
      output.height == input.height
    else { throw ProcessError.sizeMismatch }
    let starless = try ["r", "g", "b"].map {
      try LayerPlane(Self.starlessLayer + "." + $0).texture(
        in: context.layers, width: input.width, height: input.height)
    }
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("star layer encoder")
    }
    encoder.setComputePipelineState(pipeline)
    for (index, plane) in input.planes.enumerated() { encoder.setTexture(plane, index: index) }
    for (index, plane) in starless.enumerated() { encoder.setTexture(plane, index: 3 + index) }
    for (index, plane) in output.planes.enumerated() { encoder.setTexture(plane, index: 6 + index) }
    var values: [Float] = [
      Float(params.number("chroma")), Float(params.number("presence")),
      params.choice("mode") == "screen" ? 1 : 0,
    ]
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }
}
