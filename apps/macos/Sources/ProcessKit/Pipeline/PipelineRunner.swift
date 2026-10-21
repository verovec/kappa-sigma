package import Foundation
package import ImageKit
package import Metal

/// Runs a `Pipeline` through a `History` (card 0059): each step's recipe applied in order, a
/// halt before every breakpoint, locked steps taken from the previous history on replay.
///
/// GPU processes come from the registry; batch processes (host tools: StarNet, GraXpert) are
/// closures the caller injects, so ProcessKit never imports StackKit. Nothing measures the image:
/// the bundle's statistics and layers are given (R2). `History` and the GPU objects are not
/// `Sendable`: a caller on the main actor hops off it around the whole run; the run checks for
/// cancellation between steps.
package final class PipelineRunner {
  /// A batch process: a host tool run on the whole image (StarNet, GraXpert).
  package struct BatchProcess: Sendable {
    /// Its parameters (what its recipe's values are validated on).
    package let schema: ParamSchema
    /// The image, its values and a progress callback (0…1) → the processed image.
    package let run:
      @Sendable (AstroImage, ParamSet, @escaping @Sendable (Double) -> Void) async throws
        -> AstroImage

    /// A batch process of `schema` running `run`.
    package init(
      schema: ParamSchema,
      run:
        @escaping @Sendable (AstroImage, ParamSet, @escaping @Sendable (Double) -> Void)
        async throws -> AstroImage
    ) {
      self.schema = schema
      self.run = run
    }
  }

  /// What the run did, step by step (indexes in the pipeline).
  package enum Event: Equatable, Sendable {
    /// The step was applied.
    case applied(Int)
    /// The locked step's earlier output was kept.
    case reused(Int)
    /// The run halted before this breakpoint.
    case stopped(Int)
    /// A batch step reported its progress, as it goes.
    case progress(Int, Double)
  }

  /// Receives the events, from the run's task (a batch tool's progress from the tool's).
  package typealias EventSink = @Sendable (Event) -> Void

  /// How a run ended.
  package enum Outcome: Equatable, Sendable {
    /// Every step ran.
    case finished
    /// Halted before the breakpoint at this index.
    case stopped(at: Int)
  }

  /// A replay: its new history and how it ended.
  package struct Replay {
    /// The history the pipeline was applied to.
    package let history: History
    /// Finished, or stopped at a breakpoint.
    package let outcome: Outcome
  }

  private let registry: ProcessRegistry
  private let device: MTLDevice
  private let runner: ProcessRunner
  private let batch: [String: BatchProcess]

  /// A runner of the processes of `registry` on `device`, and of the `batch` tools by id.
  package init(
    registry: ProcessRegistry, device: MTLDevice, batch: [String: BatchProcess] = [:]
  ) throws {
    self.registry = registry
    self.device = device
    runner = try ProcessRunner(device: device)
    self.batch = batch
  }

  /// Applies `pipeline` to `history` from step `start` against `bundle`.
  ///
  /// The run halts before the first breakpoint; a locked step reuses the same step of `previous`
  /// when that output was made from the same image by the same earlier steps (`PipelineReuse`).
  package func run(
    _ pipeline: Pipeline, on history: History, bundle: PipelineBundle, from start: Int = 0,
    previous: History? = nil, onEvent: @escaping EventSink = { _ in }
  ) async throws -> Outcome {
    for index in pipeline.steps.indices where index >= start {
      try Task.checkCancellation()
      let step = pipeline.steps[index]
      if step.mode == .stop {
        onEvent(.stopped(index))
        return .stopped(at: index)
      }
      try await apply(
        step, at: index, on: history, bundle: bundle, previous: previous, onEvent: onEvent)
    }
    return .finished
  }

  /// The user's « Continue » at the breakpoint `index`: applies it with `params` (the values
  /// edited in the panel, the recipe's otherwise), then runs on to the next breakpoint, locked
  /// steps still taken from `previous`.
  package func resume(
    _ pipeline: Pipeline, at index: Int, on history: History, bundle: PipelineBundle,
    params: ParamSet? = nil, previous: History? = nil, onEvent: @escaping EventSink = { _ in }
  ) async throws -> Outcome {
    guard pipeline.steps.indices.contains(index) else { throw PipelineError.noStep(index) }
    var step = pipeline.steps[index]
    if let params { step.recipe = Recipe(processID: step.recipe.processID, params: params) }
    step.mode = .auto
    step.locked = false
    try await apply(
      step, at: index, on: history, bundle: bundle, previous: nil, onEvent: onEvent)
    return try await run(
      pipeline, on: history, bundle: bundle, from: index + 1, previous: previous,
      onEvent: onEvent)
  }

  /// `pipeline` replayed on `image` (another bundle, or the same one again) in a new history
  /// in `directory`, up to its first breakpoint; locked steps come from `previous`.
  package func replay(
    _ pipeline: Pipeline, on image: AstroImage, header: FITSHeader? = nil, in directory: URL,
    bundle: PipelineBundle, previous: History? = nil, onEvent: @escaping EventSink = { _ in }
  ) async throws -> Replay {
    let history = try History(directory: directory, original: image, header: header)
    let outcome = try await run(
      pipeline, on: history, bundle: bundle, previous: previous, onEvent: onEvent)
    return Replay(history: history, outcome: outcome)
  }

  private func apply(
    _ step: PipelineStep, at index: Int, on history: History, bundle: PipelineBundle,
    previous: History?, onEvent: @escaping EventSink
  ) async throws {
    let id = step.recipe.processID
    if step.locked, let previous,
      PipelineReuse.canReuse(step: index, of: previous, into: history, processID: id)
    {
      try history.apply(
        processID: id, params: previous.steps[index].params,
        result: previous.output(ofStep: index))
      onEvent(.reused(index))
      return
    }
    if let type = registry.type(id: id) {
      let params = try Self.values(of: step, schema: type.schema, at: index)
      let process = try type.init(params: params, device: device)
      let input = history.current
      let layers = try bundle.layers.mapValues { try GPUImage(device: device, image: $0) }
      let output = try runner.run(
        process, input: GPUImage(device: device, image: input), stats: bundle.stats,
        layers: layers, layerStats: bundle.layerStats)
      let result = AstroImage(
        width: input.width, height: input.height, planes: output.read(), metadata: input.metadata)
      try history.apply(processID: id, params: params, result: result)
    } else if let tool = batch[id] {
      let params = try Self.values(of: step, schema: tool.schema, at: index)
      let result = try await tool.run(history.current, params) { onEvent(.progress(index, $0)) }
      try history.apply(processID: id, params: params, result: result)
    } else {
      throw PipelineError.unknownProcess(id)
    }
    onEvent(.applied(index))
  }

  /// The step's values on `schema`; a value the schema refuses stops the run with its name
  /// (never a default silently applied in its place, R2).
  private static func values(of step: PipelineStep, schema: ParamSchema, at index: Int) throws
    -> ParamSet
  {
    let loaded = ParamSet.loading(step.recipe.params, onto: schema)
    guard loaded.rejected.isEmpty else {
      throw PipelineError.invalidValues(step: index, ids: loaded.rejected.map(\.id))
    }
    return loaded.params
  }
}
