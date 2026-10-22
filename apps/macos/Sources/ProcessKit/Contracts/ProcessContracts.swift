package import Metal

/// The contracts every registered process passes (design §4.6).
///
/// They run on a test input:
///
/// - **PreviewEqualsApply**: the preview render is bit-identical to the Apply render.
/// - **NoHiddenState**: two renders with the same inputs are bit-identical.
/// - **PxUnitsScale**: a `.px` value `v` at scale 2 renders exactly like `v / 2` at scale 1,
///   so `render` divides every pixel parameter by the scale and nothing else depends on it.
///
/// A `GeometricProcess` runs without the mask check (it refuses a mask: a moved grid has no
/// input pixel under each output pixel).
package struct ProcessContracts {
  /// One of the three contracts.
  package enum Contract: String, CaseIterable, Sendable {
    /// Preview = Apply.
    case previewEqualsApply
    /// Same inputs, same output.
    case noHiddenState
    /// Pixel parameters scale with the preview level.
    case pxUnitsScale
  }

  /// A broken contract and how.
  package struct Violation: Equatable, Sendable {
    /// The contract.
    package let contract: Contract
    /// What differed.
    package let detail: String
  }

  private let device: MTLDevice
  private let runner: ProcessRunner
  private let input: GPUImage
  private let stats: LayerStats
  private let layers: [String: GPUImage]
  private let layerStats: [String: LayerStats]
  /// 1 on the left half, 0 on the right: every process also runs under it.
  private let halfMask: GPUImage

  /// Contracts run on `input` (non-uniform, so any change shows) with `stats` and the bundle
  /// `layers` a process reads, with their bundle statistics `layerStats`.
  package init(
    device: MTLDevice, input: GPUImage, stats: LayerStats, layers: [String: GPUImage] = [:],
    layerStats: [String: LayerStats] = [:]
  ) throws {
    self.device = device
    runner = try ProcessRunner(device: device)
    self.input = input
    self.stats = stats
    self.layers = layers
    self.layerStats = layerStats
    let row = (0..<input.width).map { Float($0 < input.width / 2 ? 1 : 0) }
    halfMask = try GPUImage(
      device: device, width: input.width, height: input.height,
      planes: [Array([[Float]](repeating: row, count: input.height).joined())])
  }

  /// Every contract `type` breaks with `params` (empty: it passes).
  ///
  /// The pixel-scale check sets each `.px` value to its upper bound, or to `pixelProbes[id]`
  /// when the bound does not fit the test input (a crop of 100 000 px on a 32 px image).
  package func violations(
    of type: any ImageProcess.Type, params: ParamSet, pixelProbes: [String: Double] = [:]
  ) throws -> [Violation] {
    var found: [Violation] = []
    let process = try type.init(params: params, device: device)
    let preview = try render(process, purpose: .preview)
    let apply = try render(process, purpose: .apply)
    if !Self.identical(preview, apply) {
      found.append(Violation(contract: .previewEqualsApply, detail: "preview ≠ apply at 1:1"))
    }
    if !(process is any GeometricProcess), let detail = try maskedViolation(of: process) {
      found.append(Violation(contract: .previewEqualsApply, detail: detail))
    }
    if !Self.identical(apply, try render(process, purpose: .apply)) {
      found.append(Violation(contract: .noHiddenState, detail: "a second render differs"))
    }
    for id in type.schema.pixelParameters {
      if let detail = try pixelScaleViolation(
        of: type, params: params, id: id, probe: pixelProbes[id])
      {
        found.append(Violation(contract: .pxUnitsScale, detail: detail))
      }
    }
    return found
  }

  /// Under the half mask: preview = apply, and the unmasked half is the input, bit for bit.
  private func maskedViolation(of process: any ImageProcess) throws -> String? {
    let preview = try render(process, purpose: .preview, mask: halfMask)
    let apply = try render(process, purpose: .apply, mask: halfMask)
    guard Self.identical(preview, apply) else { return "preview ≠ apply under a mask" }
    let original = input.read()
    for (plane, values) in apply.enumerated() {
      for (index, value) in values.enumerated()
      where index % input.width >= input.width / 2
        && value.bitPattern != original[plane][index].bitPattern
      {
        return "the unmasked half changed under a mask"
      }
    }
    return nil
  }

  /// `id` at its upper bound (or `probe`) `v`, scale 2, against `v / 2` at scale 1, every other
  /// `.px` value halved with it.
  private func pixelScaleViolation(
    of type: any ImageProcess.Type, params: ParamSet, id: String, probe: Double?
  ) throws -> String? {
    guard case .number(_, let bounds)? = type.schema.spec(id)?.kind else { return nil }
    let full = probe ?? bounds.upperBound
    let half = full / 2
    guard half >= bounds.lowerBound, full > 0 else {
      return "\(id): bounds \(bounds) leave no value v with v / 2 in bounds"
    }
    var atFull = params
    try atFull.set(id, .number(full))
    // Every other pixel parameter is halved too: at scale 2 the process divides all of them. A
    // half below its bound would be clamped, and the reference would compare the wrong values.
    var atHalf = atFull
    for other in type.schema.pixelParameters {
      let value = atFull.number(other) / 2
      if case .number(_, let otherBounds)? = type.schema.spec(other)?.kind,
        value < otherBounds.lowerBound
      {
        return "\(other) = \(value * 2): v / 2 is below its bounds \(otherBounds)"
      }
      try atHalf.set(other, .number(value))
    }
    let scaled = try render(type.init(params: atFull, device: device), scale: 2)
    let reference = try render(type.init(params: atHalf, device: device), scale: 1)
    let halved = type.schema.pixelParameters.map { "\($0) = \(atHalf.number($0))" }
    return Self.identical(scaled, reference)
      ? nil
      : "\(id) = \(full) at scale 2 ≠ \(halved.joined(separator: ", ")) at scale 1"
  }

  private func render(
    _ process: any ImageProcess, scale: Double = 1, purpose: RenderContext.Purpose = .apply,
    mask: GPUImage? = nil
  ) throws -> [[Float]] {
    try runner.run(
      process, input: input, stats: stats, scale: scale, purpose: purpose, layers: layers,
      layerStats: layerStats,
      mask: mask
    ).read()
  }

  /// Bit-identical planes (NaN included).
  private static func identical(_ lhs: [[Float]], _ rhs: [[Float]]) -> Bool {
    lhs.map { $0.map(\.bitPattern) } == rhs.map { $0.map(\.bitPattern) }
  }
}
