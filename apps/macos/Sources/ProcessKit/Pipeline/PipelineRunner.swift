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
  /// The run halts before the first breakpoint; a locked step reuses the same step of
  /// `previous` when that output was made from the same input (`PipelineReuse`).
  package func run(
    _ pipeline: Pipeline, on history: History, bundle: PipelineBundle, from start: Int = 0,
    previous: PipelineRun? = nil, onEvent: @escaping EventSink = { _ in }
  ) async throws -> Outcome {
    let session = try Session(
      history: history, bundle: bundle, device: device, previous: previous, onEvent: onEvent)
    return try await steps(of: pipeline, from: start, in: session)
  }

  /// The user's « Continue » at the breakpoint `index`: applies it with `params` (the values
  /// edited in the panel, the recipe's otherwise), then runs on to the next breakpoint, locked
  /// steps still taken from `previous`.
  ///
  /// Refused unless `history` stands at that breakpoint (it holds exactly the steps before it):
  /// after an undo, Continue would apply the step to another image.
  package func resume(
    _ pipeline: Pipeline, at index: Int, on history: History, bundle: PipelineBundle,
    params: ParamSet? = nil, previous: PipelineRun? = nil, onEvent: @escaping EventSink = { _ in }
  ) async throws -> Outcome {
    guard pipeline.steps.indices.contains(index) else { throw PipelineError.noStep(index) }
    guard pipeline.steps[index].mode == .stop, history.steps.count == index else {
      throw PipelineError.notAtBreakpoint(step: index, steps: history.steps.count)
    }
    try Task.checkCancellation()
    var step = pipeline.steps[index]
    if let params { step.recipe = Recipe(processID: step.recipe.processID, params: params) }
    step.mode = .auto
    step.locked = false
    let session = try Session(
      history: history, bundle: bundle, device: device, previous: previous, onEvent: onEvent)
    try await apply(step, at: index, in: session)
    return try await steps(of: pipeline, from: index + 1, in: session)
  }

  /// `pipeline` replayed on `image` (another bundle, or the same one again) in a new history
  /// in `directory`, up to its first breakpoint; locked steps come from `previous`.
  package func replay(
    _ pipeline: Pipeline, on image: AstroImage, header: FITSHeader? = nil, in directory: URL,
    bundle: PipelineBundle, previous: PipelineRun? = nil, onEvent: @escaping EventSink = { _ in }
  ) async throws -> Replay {
    let history = try History(directory: directory, original: image, header: header)
    let outcome = try await run(
      pipeline, on: history, bundle: bundle, previous: previous, onEvent: onEvent)
    return Replay(history: history, outcome: outcome)
  }

  /// What the steps of one run share: the bundle's layers are uploaded once.
  private struct Session {
    let history: History
    let bundle: PipelineBundle
    let layers: [String: GPUImage]
    let previous: PipelineRun?
    let onEvent: EventSink

    init(
      history: History, bundle: PipelineBundle, device: MTLDevice, previous: PipelineRun?,
      onEvent: @escaping EventSink
    ) throws {
      self.history = history
      self.bundle = bundle
      layers = try bundle.layers.mapValues { try GPUImage(device: device, image: $0) }
      self.previous = previous
      self.onEvent = onEvent
    }

    /// The statistics a step gets: the bundle's for the original image, else those of the image
    /// the step receives (as the Studio shows for it).
    var stats: LayerStats {
      history.steps.isEmpty ? bundle.stats : LayerStats.measured(history.current)
    }
  }

  private func steps(of pipeline: Pipeline, from start: Int, in session: Session) async throws
    -> Outcome
  {
    for index in pipeline.steps.indices where index >= start {
      try Task.checkCancellation()
      let step = pipeline.steps[index]
      if step.mode == .stop {
        session.onEvent(.stopped(index))
        return .stopped(at: index)
      }
      try await apply(step, at: index, in: session)
    }
    return .finished
  }

  private func apply(_ step: PipelineStep, at index: Int, in session: Session) async throws {
    let (id, history) = (step.recipe.processID, session.history)
    if step.locked, let previous = session.previous,
      PipelineReuse.canReuse(
        step: index, of: previous, into: history, bundle: session.bundle, processID: id)
    {
      let written = try previous.history.written(ofStep: index)
      try history.apply(
        processID: id, params: previous.history.steps[index].params,
        result: previous.history.output(ofStep: index), outputs: written.outputs,
        replacing: written.replaced)
      session.onEvent(.reused(index))
      return
    }
    if let tool = batch[id], registry.type(id: id).map({ step.recipe.runsTool(as: $0) }) ?? true {
      let params = try Self.values(of: step, schema: tool.schema, at: index)
      let onEvent = session.onEvent
      try await tool.record(
        id, params: params, in: history, bundle: session.bundle
      ) { onEvent(.progress(index, $0)) }
    } else if let type = registry.type(id: id) {
      // A host-tool process's render is its preview only: without the tool, refuse.
      guard !step.recipe.runsTool(as: type) else {
        throw PipelineError.toolMissing(id)
      }
      let params = try Self.values(of: step, schema: type.schema, at: index)
      let process = try type.init(params: params, device: device)
      let input = history.current
      let (layers, layerStats) = try context(session)
      let result = try runner.image(
        process, input: input, stats: session.stats, layers: layers, layerStats: layerStats)
      // A geometry step moves the layers with its image, as in the Studio (card 0090).
      let moved = try runner.movedLayers(
        process, layers: layers, input: input, result: result, roles: history.layerRoles)
      try history.apply(
        processID: id, params: params, result: result, outputs: moved.outputs,
        replacing: moved.replacing)
    } else {
      throw PipelineError.unknownProcess(id)
    }
    session.onEvent(.applied(index))
  }

  /// The layers a step reads, as `StudioSession` gives them (`History.context`).
  private func context(_ session: Session) throws -> ([String: GPUImage], [String: LayerStats]) {
    try session.history.context(
      over: session.layers, stats: session.bundle.layerStats, device: device,
      moving: registry.movingIDs)
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
