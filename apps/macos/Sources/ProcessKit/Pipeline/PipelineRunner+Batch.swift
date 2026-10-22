package import ImageKit

extension PipelineRunner {
  /// A batch process: a host tool (StarNet, GraXpert) run on the image.
  ///
  /// It may also read the bundle's layers; its result comes back as a step (card 0092: with the
  /// layers it wrote and the bundle layers it rewrote).
  package struct BatchProcess: Sendable {
    /// One run: the input, its values and a progress callback (0…1) → the step.
    package typealias Step =
      @Sendable (BatchInput, ParamSet, @escaping @Sendable (Double) -> Void) async throws
      -> BatchOutput

    /// Its parameters (what its recipe's values are validated on).
    package let schema: ParamSchema
    /// Runs the tool.
    package let step: Step

    /// A batch process of `schema` running `step`.
    package init(schema: ParamSchema, step: @escaping Step) {
      self.schema = schema
      self.step = step
    }

    /// A batch process of `schema` whose `run` makes one image: the step's new working image,
    /// or the layer `writes` (StarNet's `starless`, card 0091) beside the unchanged one.
    package init(
      schema: ParamSchema, writes: LayerRole? = nil,
      run:
        @escaping @Sendable (AstroImage, ParamSet, @escaping @Sendable (Double) -> Void)
        async throws -> AstroImage
    ) {
      self.init(schema: schema) { input, params, progress in
        let output = try await run(input.image, params, progress)
        guard let writes else { return BatchOutput(result: output) }
        return BatchOutput(result: input.image, outputs: [writes: output])
      }
    }

    /// Runs the tool on the working image of `history` (and the layers of `bundle` as its steps
    /// left them) and records the step `id` with `params`, its layers with it.
    ///
    /// A cancel that came after the tool ended still records nothing; a history that moved
    /// meanwhile is refused (`HistoryError.movedDuring`): the step would overwrite the move.
    package func record(
      _ id: String, params: ParamSet, in history: History,
      bundle: PipelineBundle = PipelineBundle(stats: LayerStats(channels: [])),
      onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
      let before = history.steps
      let input = try BatchInput(history: history, bundle: bundle)
      let output = try await step(input, params, onProgress)
      try Task.checkCancellation()
      guard history.steps == before else { throw HistoryError.movedDuring(id) }
      try history.apply(
        processID: id, params: params, result: output.result, outputs: output.outputs,
        replacing: output.replaced)
    }
  }

  /// What a batch process reads: the head and the bundle's layers as the steps so far left
  /// them (a layer rewritten by an earlier step replaces the bundle's).
  package struct BatchInput {
    /// The working image.
    package let image: AstroImage
    /// The bundle's layers by id.
    package let layers: [String: AstroImage]

    /// An input of `image` and `layers`.
    package init(image: AstroImage, layers: [String: AstroImage]) {
      self.image = image
      self.layers = layers
    }

    /// The head of `history` and the layers of `bundle` as its steps left them.
    package init(history: History, bundle: PipelineBundle) throws {
      let context = try history.context(over: bundle.layers)
      self.init(image: history.current, layers: context.filter { bundle.layers[$0.key] != nil })
    }
  }

  /// What a batch process made: the step's image, the layers it wrote by role and the bundle
  /// layers it rewrote by id (`History.apply(…outputs:replacing:)`).
  package struct BatchOutput {
    /// The step's image.
    package let result: AstroImage
    /// New layers by role (the background model, a starless layer).
    package let outputs: [LayerRole: AstroImage]
    /// Bundle layers rewritten, by id.
    package let replaced: [String: AstroImage]

    /// A step of `result`, `outputs` and `replaced`.
    package init(
      result: AstroImage, outputs: [LayerRole: AstroImage] = [:],
      replaced: [String: AstroImage] = [:]
    ) {
      self.result = result
      self.outputs = outputs
      self.replaced = replaced
    }
  }
}
