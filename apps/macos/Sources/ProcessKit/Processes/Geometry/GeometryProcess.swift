package import ImageKit
package import Metal

/// Crop, rotate and flip the image and every layer with it (card 0090).
///
/// The values read as the image is shown: crop each edge in full-resolution pixels, then turn by
/// quarter turns clockwise, then flip the turned image; crops, turns and flips are index copies,
/// bit-exact. A fine `angle` (clockwise) then resamples about the centre with the chosen
/// interpolation, on the same canvas or one expanded to hold the turned frame; at 0 nothing is
/// resampled. The plate solution follows the exact moves and is removed after an angle (a
/// resampled frame needs a new solve), with the reason shown in the panel.
///
/// R2: no automatic crop of the stacking edges — the region tool draws it, « Use region » fills
/// the values, Apply records them.
package struct GeometryProcess: GeometricProcess {
  package static let id = "geometry"
  package static let title = "Geometry"
  package static let stage = ProcessStage.any
  package static let previewExactOnlyAt1to1 = true
  /// The quarter turns offered, in degrees clockwise.
  package static let rotations = ["0", "90", "180", "270"]
  /// The resampling kernels for a fine angle.
  package static let interpolations = ["bilinear", "bicubic", "lanczos3"]

  package static let schema = ParamSchema(
    zip(
      ["cropLeft", "cropTop", "cropRight", "cropBottom"],
      ["Crop left", "Crop top", "Crop right", "Crop bottom"]
    ).map { id, title in
      ParamSpec(id: id, title: title, unit: .px, level: .simple, number: 0, in: 0...100_000)
    } + [
      ParamSpec(id: "rotation", title: "Rotation", level: .simple, choice: "0", of: rotations),
      ParamSpec(id: "flipH", title: "Flip horizontally", level: .simple, flag: false),
      ParamSpec(id: "flipV", title: "Flip vertically", level: .simple, flag: false),
      ParamSpec(
        id: "angle", title: "Angle", unit: .none, level: .advanced, number: 0, in: -45...45),
      ParamSpec(
        id: "interpolation", title: "Interpolation", level: .advanced, choice: "lanczos3",
        of: interpolations),
      ParamSpec(
        id: "canvas", title: "Canvas", level: .advanced, choice: "keep", of: ["keep", "expand"]),
    ])

  /// Whole pixels: the crop arrows move one pixel.
  package static let steps: [String: Double] = [
    "cropLeft": 1, "cropTop": 1, "cropRight": 1, "cropBottom": 1, "angle": 0.1,
  ]

  /// Each crop slides up to one pixel short of the side it crops: a crop that leaves no pixel is
  /// refused by the plan, a larger typed value is kept as typed (R2).
  package static func displayRanges(width: Int, height: Int) -> [String: ClosedRange<Double>] {
    let across = 0...Double(max(width - 1, 0))
    let down = 0...Double(max(height - 1, 0))
    return ["cropLeft": across, "cropRight": across, "cropTop": down, "cropBottom": down]
  }

  package let params: ParamSet
  private let exact: MTLComputePipelineState
  private let resample: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    let library = try ProcessLibrary.library(device: device, file: "Geometry.metal")
    exact = try ProcessLibrary.pipeline(library: library, function: "geometry_exact")
    resample = try ProcessLibrary.pipeline(library: library, function: "geometry_resample")
  }

  /// The interpolation and canvas matter once an angle is set: shown without the disclosure.
  package static func promoted(_ params: ParamSet) -> Set<String> {
    params.number("angle") == 0 ? [] : ["interpolation", "canvas"]
  }

  /// Whether `params` leave every pixel where it is (no crop, turn, flip or angle): only then is
  /// a preview on the head's grid.
  package static func isIdentity(_ params: ParamSet) -> Bool {
    ["cropLeft", "cropTop", "cropRight", "cropBottom", "angle"].allSatisfy {
      params.number($0) == 0
    }
      && params.choice("rotation") == "0" && !params.flag("flipH") && !params.flag("flipV")
  }

  /// Whether the output loses its plate solution: a fine angle resamples the frame (the exact
  /// moves keep it, moved with the pixels).
  package static func removesWCS(_ params: ParamSet) -> Bool {
    params.number("angle") != 0
  }

  /// The full-resolution output size of `params` on a `width` × `height` image (the panel's
  /// readout, without building the pipelines).
  package static func outputSize(_ params: ParamSet, width: Int, height: Int) throws
    -> (width: Int, height: Int)
  {
    // The size does not depend on the row order: a flip conjugation keeps it.
    let plan = try GeometryPlan(
      params: params, width: width, height: height, scale: 1, bottomUp: false)
    return (plan.width, plan.height)
  }

  package func outputSize(width: Int, height: Int, scale: Double, bottomUp: Bool) throws
    -> (width: Int, height: Int)
  {
    let plan = try GeometryPlan(
      params: params, width: width, height: height, scale: scale, bottomUp: bottomUp)
    return (plan.width, plan.height)
  }

  package func header(_ header: FITSHeader, width: Int, height: Int, bottomUp: Bool) throws
    -> FITSHeader
  {
    let plan = try GeometryPlan(
      params: params, width: width, height: height, scale: 1, bottomUp: bottomUp)
    return plan.degrees == 0 ? header.moved(by: plan.map) : header.droppingWCS()
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    let plan = try GeometryPlan(
      params: params, width: input.width, height: input.height, scale: context.scale,
      bottomUp: context.rowsBottomUp)
    guard output.width == plan.width, output.height == plan.height,
      output.planes.count == input.planes.count
    else { throw ProcessError.sizeMismatch }
    let moved =
      plan.degrees == 0
      ? output
      : try GPUImage(
        device: context.commands.device, width: plan.map.width, height: plan.map.height,
        channels: input.planes.count)
    var exactValues = plan.exactUniforms
    try encode(exact, input, moved, context) { encoder in
      unsafe encoder.setBytes(
        &exactValues, length: exactValues.count * MemoryLayout<Int32>.stride, index: 0)
    }
    guard plan.degrees != 0 else { return }
    var resampleValues = plan.resampleUniforms
    try encode(resample, moved, output, context) { encoder in
      unsafe encoder.setBytes(
        &resampleValues, length: resampleValues.count * MemoryLayout<Float>.stride, index: 0)
    }
  }

  /// One dispatch per plane of `pipeline` from `source` into `target`.
  private func encode(
    _ pipeline: MTLComputePipelineState, _ source: GPUImage, _ target: GPUImage,
    _ context: RenderContext, uniforms: (MTLComputeCommandEncoder) -> Void
  ) throws {
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("geometry encoder")
    }
    encoder.setComputePipelineState(pipeline)
    uniforms(encoder)
    for (from, to) in zip(source.planes, target.planes) {
      encoder.setTexture(from, index: 0)
      encoder.setTexture(to, index: 1)
      encoder.dispatchThreads(
        MTLSize(width: target.width, height: target.height, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    }
    encoder.endEncoding()
  }
}
