package import Metal

/// A Studio process (design §2): a parameter schema, a GPU `render` used for both the preview
/// and Apply, and suggestions computed from the bundle statistics.
///
/// R2 is structural: `render` reads the image, the stats and `params`, never measures the image
/// to change its own parameters; anything measured comes back as `suggestions`, which the user
/// may accept. Every process passes `ProcessContracts` and ships a fr+en help card.
package protocol ImageProcess {
  /// Stable identifier (recipes, history, help cards): never renamed once shipped.
  static var id: String { get }
  /// Panel and menu title.
  static var title: String { get }
  /// Linear or non-linear data, for pipeline ordering (0059).
  static var stage: ProcessStage { get }
  /// The layers the process needs; a missing one greys it with the reason.
  static var requires: [LayerRole] { get }
  /// The parameters, in panel order.
  static var schema: ParamSchema { get }
  /// True when the preview is exact only at 1:1 — required for any `.px` parameter, since
  /// morphology and blurs do not commute with the pyramid.
  static var previewExactOnlyAt1to1: Bool { get }

  /// The values `render` reads.
  var params: ParamSet { get }

  /// A process with `params`, its pipelines built on `device`.
  init(params: ParamSet, device: MTLDevice) throws

  /// Encodes the process of `input` into `output` (same size, but for a `GeometricProcess`) in
  /// `context.commands`. `.px`
  /// parameters are divided by `context.scale`; nothing else depends on the purpose.
  func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) throws

  /// Values the user may apply, computed from `stats` only; never applied by the process.
  func suggestions(stats: LayerStats) -> [Suggestion]

  /// Values the user may apply, computed from `stats` and the bundle statistics of the layers
  /// the process reads (`RenderContext.layerStats`); `suggestions(stats:)` by default.
  func suggestions(stats: LayerStats, layers: [String: LayerStats]) -> [Suggestion]

  /// Every `Suggestion.reason` the process can give: English keys of its catalog (gated in fr).
  static var suggestionReasons: [String] { get }

  /// Planes of the output for an input of `input` planes (the input's count by default).
  static func outputChannels(input: Int) -> Int

  /// Advanced parameters `params` makes relevant enough to show without the disclosure
  /// (`ParamSchema.visible(disclosed:promoted:)`); none by default.
  static func promoted(_ params: ParamSet) -> Set<String>

  /// The arrow step of number parameters that need a finer one than the panel's default (a
  /// tenth of it with ⇧ or ⌥), by id.
  static var steps: [String: Double] { get }

  /// The slider range of number parameters whose useful travel depends on the image, by id, for
  /// a `width` × `height` head (full-resolution pixels); none by default. Display only: the
  /// schema bounds stay what a value is validated against (recipes are checked without an image).
  static func displayRanges(width: Int, height: Int) -> [String: ClosedRange<Double>]

  /// True when Apply runs a host tool (Siril…) the caller injects: `render` is only the preview,
  /// and recording it as the step is refused (`StudioError.needsTool`).
  static var hostTool: Bool { get }

  /// Whether `params` make Apply run the host tool — the one predicate every caller asks (a
  /// disabled step is the image itself, no tool needed: card 0094); `hostTool` by default.
  static func runsTool(_ params: ParamSet) -> Bool

  /// The choices `params` still leave to the user before its host tool may run, by parameter id
  /// (card 0140: a spec that `allowsUnset`, still unset) — never made for the user; none by
  /// default. Checked before a tool runs, so only a host-tool process may leave a choice unset
  /// (`ProcessRegistry.problems`).
  static func unchosen(_ params: ParamSet) -> [String]

  /// True when the process reads the image's plate solution (colour calibration): greyed until
  /// the head carries one.
  static var requiresSolution: Bool { get }

  /// Which bundle layers it may edit on a branch (card 0118); `.never` by default.
  static var branchable: BranchUse { get }

  /// The bundle layers `params` make it read besides its input, among `layerIDs` (card 0118: a
  /// main step is stale once a branch it read moved); none by default.
  static func layersRead(_ params: ParamSet, layerIDs: Set<String>) -> Set<String>

  /// The bundle layers whose signal `params` put into its image, among `layerIDs` (card 0131:
  /// what « Combined » says it holds) — a layer read for a continuum or a model only is not one;
  /// none by default.
  static func layersMerged(_ params: ParamSet, layerIDs: Set<String>) -> Set<String>

  /// True when its image is made of `layersMerged` alone, its input only setting the size
  /// (channel combination): what the image held before is gone.
  static var replacesInput: Bool { get }
}

extension ImageProcess {
  /// No layer requirement.
  package static var requires: [LayerRole] { [] }

  /// No suggestion.
  package func suggestions(stats: LayerStats) -> [Suggestion] { [] }

  /// The suggestions of the input's statistics alone.
  package func suggestions(stats: LayerStats, layers: [String: LayerStats]) -> [Suggestion] {
    suggestions(stats: stats)
  }

  /// No suggestion reason.
  package static var suggestionReasons: [String] { [] }

  /// As many planes as the input.
  package static func outputChannels(input: Int) -> Int { input }

  /// No promotion.
  package static func promoted(_ params: ParamSet) -> Set<String> { [] }

  /// The panel's default steps.
  package static var steps: [String: Double] { [:] }

  /// None: the panel's sliders span the schema bounds.
  package static func displayRanges(width: Int, height: Int) -> [String: ClosedRange<Double>] {
    [:]
  }

  /// A GPU process: `render` is the step.
  package static var hostTool: Bool { false }

  /// A host-tool process always runs its tool.
  package static func runsTool(_ params: ParamSet) -> Bool { hostTool }

  /// Nothing to choose.
  package static func unchosen(_ params: ParamSet) -> [String] { [] }

  /// No solution needed.
  package static var requiresSolution: Bool { false }

  /// Main history only.
  package static var branchable: BranchUse { .never }

  /// Its input only.
  package static func layersRead(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> { [] }

  /// Nothing besides its input.
  package static func layersMerged(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    []
  }

  /// Its input goes into its image.
  package static var replacesInput: Bool { false }
}

/// Where a process belongs in a pipeline.
package enum ProcessStage: String, Codable, Sendable {
  /// On linear data (before the stretch): background, colour calibration, deconvolution…
  case linear
  /// On stretched data: curves, saturation, star reduction…
  case nonlinear
  /// Either.
  case any
}

/// The encoding target and the scale of one render.
package struct RenderContext {
  /// Why the render runs: a preview frame or Apply into the history.
  package enum Purpose: Sendable {
    /// The live preview.
    case preview
    /// Apply into the history.
    case apply
  }

  /// The command buffer to encode into.
  package let commands: MTLCommandBuffer
  /// Full-resolution pixels per working pixel (1 at 1:1, 2 on the half-size level…).
  package let scale: Double
  /// Preview or Apply: `ProcessContracts` checks it changes nothing.
  package let purpose: Purpose
  /// The bundle's layers by id (`RGB`, `R`, `G`, `B`, `L`, `Ha`, `OIII`, `SII`…), at the same
  /// size as the input: what a process reads besides its input (combination, screens).
  package let layers: [String: GPUImage]
  /// The bundle statistics of `layers`, by the same ids (R2: what a process reads instead of
  /// measuring a layer).
  package let layerStats: [String: LayerStats]
  /// The input's rows are stored bottom-up (shown flipped): what a geometric process needs to
  /// read « top » and « clockwise » as the image is shown.
  package let rowsBottomUp: Bool

  /// A context encoding into `commands` at `scale` for `purpose`, with the bundle `layers` and
  /// their `layerStats`, over an input whose rows are stored bottom-up or not.
  package init(
    commands: MTLCommandBuffer, scale: Double, purpose: Purpose, layers: [String: GPUImage] = [:],
    layerStats: [String: LayerStats] = [:], rowsBottomUp: Bool = false
  ) {
    self.commands = commands
    self.scale = scale
    self.purpose = purpose
    self.layers = layers
    self.layerStats = layerStats
    self.rowsBottomUp = rowsBottomUp
  }
}

/// A value a process proposes from the statistics, with its reason; the user applies it or not.
package struct Suggestion: Equatable, Sendable {
  /// The parameter it would set.
  package let paramID: String
  /// The proposed value.
  package let value: ParamValue
  /// Why, in a sentence the panel shows.
  package let reason: String
  /// What the reason is about, shown as is next to it (card 0130: the catalogue object's name);
  /// nil for a reason that says it all.
  package let subject: String?

  /// A proposal of `value` for `paramID`, because `reason` (about `subject`).
  package init(paramID: String, value: ParamValue, reason: String, subject: String? = nil) {
    self.paramID = paramID
    self.value = value
    self.reason = reason
    self.subject = subject
  }
}

/// A process failure, with what the user or a test can act on.
package enum ProcessError: Error, Equatable, Sendable {
  /// A shader did not compile or a function is missing.
  case shader(String)
  /// A command buffer, encoder or texture could not be made, or the GPU reported an error.
  case commandFailed(String)
  /// Two images of different sizes or plane counts where one size is required.
  case sizeMismatch
  /// A layer the parameters need is not in the bundle (never replaced by another one, R2).
  case missingLayer(String)
  /// A mask or parameter value that cannot be computed (a zero threshold, low > high…).
  case invalidParameter(String)
}
