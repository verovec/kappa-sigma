package import Foundation
package import ImageKit
package import Metal

/// Runs a `Pipeline` through a `History` (card 0059): each step's recipe applied in order, a
/// halt before every breakpoint, locked steps taken from the previous history on replay.
///
/// GPU processes come from the registry; batch processes (host tools: StarNet, GraXpert) are
/// closures the caller injects, so ProcessKit never imports StackKit. Nothing measures the image:
/// the bundle statistics are given (R2).
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
    /// A batch step reported its progress.
    case progress(Int, Double)
  }

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

  /// Applies `pipeline` to `history` from step `start`, halting before the first breakpoint;
  /// a locked step reuses the same step of `previous` when it ran the same process.
  package func run(
    _ pipeline: Pipeline, on history: History, stats: LayerStats, from start: Int = 0,
    previous: History? = nil, onEvent: (Event) -> Void = { _ in }
  ) async throws -> Outcome {
    for index in pipeline.steps.indices where index >= start {
      let step = pipeline.steps[index]
      if step.mode == .stop {
        onEvent(.stopped(index))
        return .stopped(at: index)
      }
      try await apply(
        step, at: index, on: history, stats: stats, previous: previous, onEvent: onEvent)
    }
    return .finished
  }

  /// The user's « Continue » at the breakpoint `index`: applies it with `params` (the values
  /// edited in the panel, the recipe's otherwise), then runs on to the next breakpoint.
  package func resume(
    _ pipeline: Pipeline, at index: Int, on history: History, stats: LayerStats,
    params: ParamSet? = nil, onEvent: (Event) -> Void = { _ in }
  ) async throws -> Outcome {
    guard pipeline.steps.indices.contains(index) else { throw PipelineError.noStep(index) }
    var step = pipeline.steps[index]
    if let params { step.recipe = Recipe(processID: step.recipe.processID, params: params) }
    step.mode = .auto
    try await apply(step, at: index, on: history, stats: stats, previous: nil, onEvent: onEvent)
    return try await run(pipeline, on: history, stats: stats, from: index + 1, onEvent: onEvent)
  }

  /// `pipeline` replayed on `image` (another bundle, or the same one again) in a new history
  /// in `directory`, up to its first breakpoint; locked steps come from `previous`.
  package func replay(
    _ pipeline: Pipeline, on image: AstroImage, header: FITSHeader? = nil, in directory: URL,
    stats: LayerStats, previous: History? = nil, onEvent: (Event) -> Void = { _ in }
  ) async throws -> Replay {
    let history = try History(directory: directory, original: image, header: header)
    let outcome = try await run(
      pipeline, on: history, stats: stats, previous: previous, onEvent: onEvent)
    return Replay(history: history, outcome: outcome)
  }

  private func apply(
    _ step: PipelineStep, at index: Int, on history: History, stats: LayerStats,
    previous: History?, onEvent: (Event) -> Void
  ) async throws {
    let id = step.recipe.processID
    if step.locked, let previous, previous.steps.indices.contains(index),
      previous.steps[index].processID == id
    {
      let kept = previous.steps[index]
      try history.apply(processID: id, params: kept.params, result: previous.output(ofStep: index))
      onEvent(.reused(index))
      return
    }
    if let type = registry.type(id: id) {
      let params = ParamSet.loading(step.recipe.params, onto: type.schema).params
      let process = try type.init(params: params, device: device)
      let input = history.current
      let output = try runner.run(
        process, input: GPUImage(device: device, image: input), stats: stats)
      let result = AstroImage(
        width: input.width, height: input.height, planes: output.read(), metadata: input.metadata)
      try history.apply(processID: id, params: params, result: result)
    } else if let tool = batch[id] {
      let params = ParamSet.loading(step.recipe.params, onto: tool.schema).params
      let progress = ProgressRelay()
      let result = try await tool.run(history.current, params) { progress.append($0) }
      // The tool reports from its own task; the events are handed over once it returns.
      for value in progress.values { onEvent(.progress(index, value)) }
      try history.apply(processID: id, params: params, result: result)
    } else {
      throw PipelineError.unknownProcess(id)
    }
    onEvent(.applied(index))
  }
}
