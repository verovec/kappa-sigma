package import Metal

/// The contracts every registered process passes (design §4.6).
///
/// They run on a test input:
///
/// - **PreviewEqualsApply**: the preview render is bit-identical to the Apply render.
/// - **NoHiddenState**: two renders with the same inputs are bit-identical.
/// - **PxUnitsScale**: a `.px` value `v` at scale 2 renders exactly like `v / 2` at scale 1,
///   so `render` divides every pixel parameter by the scale and nothing else depends on it.
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

  /// Contracts run on `input` (non-uniform, so any change shows) with `stats`.
  package init(device: MTLDevice, input: GPUImage, stats: LayerStats) throws {
    self.device = device
    runner = try ProcessRunner(device: device)
    self.input = input
    self.stats = stats
  }

  /// Every contract `type` breaks with `params` (empty: it passes).
  package func violations(of type: any ImageProcess.Type, params: ParamSet) throws -> [Violation] {
    var found: [Violation] = []
    let process = try type.init(params: params, device: device)
    let preview = try render(process, purpose: .preview)
    let apply = try render(process, purpose: .apply)
    if !Self.identical(preview, apply) {
      found.append(Violation(contract: .previewEqualsApply, detail: "preview ≠ apply at 1:1"))
    }
    if !Self.identical(apply, try render(process, purpose: .apply)) {
      found.append(Violation(contract: .noHiddenState, detail: "a second render differs"))
    }
    for id in type.schema.pixelParameters {
      if let detail = try pixelScaleViolation(of: type, params: params, id: id) {
        found.append(Violation(contract: .pxUnitsScale, detail: detail))
      }
    }
    return found
  }

  /// `id` at its upper bound `v`, scale 2, against `v / 2` at scale 1.
  private func pixelScaleViolation(
    of type: any ImageProcess.Type, params: ParamSet, id: String
  ) throws -> String? {
    guard case .number(_, let bounds)? = type.schema.spec(id)?.kind else { return nil }
    let full = bounds.upperBound
    let half = full / 2
    guard half >= bounds.lowerBound, full > 0 else {
      return "\(id): bounds \(bounds) leave no value v with v / 2 in bounds"
    }
    var atFull = params
    try atFull.set(id, .number(full))
    var atHalf = params
    try atHalf.set(id, .number(half))
    let scaled = try render(type.init(params: atFull, device: device), scale: 2)
    let reference = try render(type.init(params: atHalf, device: device), scale: 1)
    return Self.identical(scaled, reference)
      ? nil : "\(id) = \(full) at scale 2 ≠ \(id) = \(half) at scale 1"
  }

  private func render(
    _ process: any ImageProcess, scale: Double = 1, purpose: RenderContext.Purpose = .apply
  ) throws -> [[Float]] {
    try runner.run(process, input: input, stats: stats, scale: scale, purpose: purpose).read()
  }

  /// Bit-identical planes (NaN included).
  private static func identical(_ lhs: [[Float]], _ rhs: [[Float]]) -> Bool {
    lhs.map { $0.map(\.bitPattern) } == rhs.map { $0.map(\.bitPattern) }
  }
}
