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

    /// A batch process of `schema` whose `run` makes the step's image alone.
    package init(
      schema: ParamSchema,
      run:
        @escaping @Sendable (AstroImage, ParamSet, @escaping @Sendable (Double) -> Void)
        async throws -> AstroImage
    ) {
      self.init(schema: schema) { input, params, progress in
        BatchOutput(result: try await run(input.image, params, progress))
      }
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
