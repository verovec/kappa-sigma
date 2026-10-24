package import ImageKit
package import Metal

/// Background extraction (design §3.2, card 0092): the engine the user chose — GraXpert's AI
/// model, Siril `subsky -rbf` or a Siril polynomial — removes the gradient of the head and, as
/// `applyTo` says, of the bundle's line or colour layers; the model is kept as a step output.
///
/// A host-tool process (`hostTool`, card 0093's seam): Apply runs the engine (StackKit
/// `BackgroundExtraction`, wired by the app as an `Extract`) through `run(_:params:extract:)`;
/// the preview is the image itself. An engine whose tool is missing is refused with the tool's
/// reason; no other engine runs in its place (R2).
package struct BackgroundExtractionProcess: ImageProcess {
  package static let id = "background-extraction"
  package static let title = "Background extraction"
  package static let stage = ProcessStage.linear
  package static let hostTool = true
  package static let previewExactOnlyAt1to1 = false

  /// The engines, in the panel's order: GraXpert, Siril RBF, Siril polynomial.
  package static let engines = ["graxpert", "siril-rbf", "siril-polynomial"]
  /// Subtract (gradients, light pollution) or divide (vignetting).
  package static let corrections = ["subtract", "divide"]
  /// The working image, the emission-line layers, or the image and every bundle layer.
  package static let scopes = ["rgb", "lines", "all"]

  package static let schema = ParamSchema([
    ParamSpec(id: "engine", title: "Engine", level: .simple, choice: "graxpert", of: engines),
    ParamSpec(
      id: "smoothing", title: "Smoothing", unit: .none, level: .advanced, number: 0, in: 0...1),
    ParamSpec(
      id: "correction", title: "Correction", level: .simple, choice: "subtract", of: corrections),
    ParamSpec(id: "applyTo", title: "Apply to", level: .simple, choice: "rgb", of: scopes),
    ParamSpec(
      id: "rbfSmooth", title: "RBF smoothing", unit: .none, level: .advanced, number: 0.5,
      in: 0...1),
    ParamSpec(
      id: "samples", title: "Samples per line", unit: .none, level: .advanced, number: 30,
      in: 1...200),
    ParamSpec(
      id: "tolerance", title: "Sample tolerance", unit: .sigma, level: .advanced, number: 1.5,
      in: 0...10),
    ParamSpec(id: "dither", title: "Dither", level: .advanced, flag: true),
    ParamSpec(
      id: "degree", title: "Polynomial degree", unit: .none, level: .advanced, number: 1,
      in: 1...4),
  ])

  package static let steps: [String: Double] = [
    "smoothing": 0.05, "rbfSmooth": 0.05, "samples": 1, "tolerance": 0.1, "degree": 1,
  ]

  /// The values of the chosen engine, shown without the disclosure.
  package static func promoted(_ params: ParamSet) -> Set<String> {
    switch params["engine"] {
    case .choice("graxpert"): ["smoothing"]
    case .choice("siril-rbf"): ["rbfSmooth", "samples", "tolerance", "dither"]
    case .choice("siril-polynomial"): ["degree"]
    default: []
    }
  }

  package let params: ParamSet

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
  }

  /// The preview: the image itself (the tool's result is shown once Apply ran it).
  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try ColourKernel.copy(input, into: output, commands: context.commands)
  }

  // MARK: - Batch

  /// One extraction of `image` with `params`, reporting 0…1: its corrected image and model.
  package typealias Extract =
    @Sendable (AstroImage, ParamSet, @escaping @Sendable (Double) -> Void) async throws
    -> (corrected: AstroImage, model: AstroImage)

  /// What a run rewrites: the working image, and bundle layers by id (sorted).
  package struct Targets: Equatable, Sendable {
    /// The working image is corrected (else kept as it is).
    package let head: Bool
    /// The bundle layers corrected, by id.
    package let layers: [String]

    /// Targets `head` (or not) and `layers`.
    package init(head: Bool, layers: [String]) {
      self.head = head
      self.layers = layers
    }
  }

  /// The bundle layers it corrects besides the working image.
  package static func layersRead(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    Set(targets(params, layerIDs: layerIDs).layers)
  }

  /// What `params` rewrites over a bundle of `layerIDs`.
  package static func targets(_ params: ParamSet, layerIDs: some Collection<String>) -> Targets {
    let lines = Set(EmissionLine.allCases.map(\.layerID))
    switch params["applyTo"] {
    case .choice("lines"):
      return Targets(head: false, layers: layerIDs.filter(lines.contains).sorted())
    case .choice("all"):
      // Image layers only: a layer named as a step role (a bundled `starless`) is not one.
      let images = layerIDs.filter { LayerRole(rawValue: $0) == nil }
      return Targets(head: true, layers: images.sorted())
    default: return Targets(head: true, layers: [])
    }
  }

  /// `extract` on every target of `params`, in order (the head first): the step's image is the
  /// corrected head (the head itself when only lines are corrected), the model of the first
  /// target is its `backgroundModel` output, the corrected layers replace the bundle's.
  package static func run(
    _ input: PipelineRunner.BatchInput, params: ParamSet, extract: Extract,
    progress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> PipelineRunner.BatchOutput {
    let targets = targets(params, layerIDs: input.layers.keys)
    let images =
      (targets.head ? [input.image] : []) + targets.layers.compactMap { input.layers[$0] }
    guard !images.isEmpty else {
      throw ProcessError.missingLayer("an emission line layer (Ha, OIII, SII)")
    }
    var pairs: [(corrected: AstroImage, model: AstroImage)] = []
    for image in images {
      try Task.checkCancellation()
      let start = Double(pairs.count)
      let count = Double(images.count)
      pairs.append(try await extract(image, params) { progress((start + $0) / count) })
    }
    let corrected = targets.head ? Array(pairs.dropFirst()) : pairs
    return PipelineRunner.BatchOutput(
      result: targets.head ? pairs[0].corrected : input.image,
      outputs: [.backgroundModel: pairs[0].model],
      replaced: Dictionary(
        uniqueKeysWithValues: zip(targets.layers, corrected.map(\.corrected))))
  }
}
