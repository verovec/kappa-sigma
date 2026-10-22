package import Foundation
internal import Observation
package import ProcessKit
package import ProjectKit
internal import os

/// The Studio's pipeline column (card 0088, design §5 B–C, R5): the steps of the pipeline with
/// what is done, where the run stands and what comes next; Run, Continue at a breakpoint, a
/// manual Apply recorded as a step, replay from another stack's run.
///
/// Nothing runs by itself: the user presses Run. A run applies the steps through
/// `PipelineRunner` on the workspace's history, then the viewer, the panel and the project
/// follow. Pipeline step `i` is history step `i` (step 0 is the channel combination of both).
@Observable
package final class PipelineSidebarModel {
  /// Where a step stands.
  package enum Status: Equatable, Sendable {
    /// Applied: the history holds it.
    case done
    /// The run halted before it; its process is in the panel.
    case current
    /// Not reached yet.
    case next
  }

  /// The pipeline shown (edited by the user's toggles, Continue values and manual Applies).
  package private(set) var pipeline: Pipeline
  /// The breakpoint the run halted at, if any.
  package private(set) var stoppedAt: Int?
  /// A batch step's progress (0…1) while it runs, by step.
  package private(set) var progress: [Int: Double] = [:]
  /// What loading the pipeline ignored or changed (unknown keys, clamped values).
  package private(set) var warnings: [String] = []
  /// What the last run did, step by step.
  package private(set) var events: [PipelineRunner.Event] = []
  /// A run is going on.
  package private(set) var isRunning = false
  /// Why the last action failed.
  package internal(set) var failure: LocalizedStringResource?
  /// Opens the window's Replay chooser (the column's « Replay on… » button).
  @ObservationIgnored package var onReplay: () -> Void = {}
  /// The last run on this stack: what a replay's locked steps may reuse.
  @ObservationIgnored package private(set) var lastRun: PipelineRun?

  @ObservationIgnored let workspace: StudioWorkspaceModel
  @ObservationIgnored let store: ProjectStore
  @ObservationIgnored private let runner: PipelineRunner
  @ObservationIgnored private let base: Set<LayerRole>

  /// The column of `workspace` showing `pipeline` (with the `warnings` its loading gave),
  /// saving to and loading from `store`; `base` holds the bundle's layer roles.
  package init(
    workspace: StudioWorkspaceModel, pipeline: Pipeline, warnings: [String] = [],
    store: ProjectStore, base: Set<LayerRole>
  ) throws {
    self.workspace = workspace
    self.pipeline = pipeline
    self.warnings = warnings
    self.store = store
    self.base = base
    let session = workspace.studio.session
    runner = try PipelineRunner(registry: session.registry, device: session.device)
  }

  /// Whether Continue can run: halted at a breakpoint whose process the panel shows.
  package var canContinue: Bool {
    guard let index = stoppedAt, pipeline.steps.indices.contains(index) else { return false }
    return workspace.panel?.type.id == pipeline.steps[index].recipe.processID
  }

  /// Where step `index` stands.
  package func status(of index: Int) -> Status {
    if index < workspace.studio.steps.count { return .done }
    return index == stoppedAt ? .current : .next
  }

  /// Why each step cannot run as ordered on this bundle (empty when it can): shown greyed.
  package var stepProblems: [[String]] {
    pipeline.stepProblems(
      registry: workspace.registry, present: workspace.studio.session.presentRoles(base: base))
  }

  /// Sets step `index` to run automatically or halt before it.
  package func setMode(_ mode: PipelineStep.Mode, of index: Int) {
    guard pipeline.steps.indices.contains(index) else { return }
    pipeline.steps[index].mode = mode
  }

  /// Locks step `index` (kept as applied on replay) or unlocks it.
  package func setLocked(_ locked: Bool, of index: Int) {
    guard pipeline.steps.indices.contains(index) else { return }
    pipeline.steps[index].locked = locked
  }

  /// Replaces the pipeline (loaded or replayed), with what its loading reported.
  package func show(_ pipeline: Pipeline, warnings: [String] = []) {
    self.pipeline = pipeline
    self.warnings = warnings
    stoppedAt = nil
  }

  /// Runs the pipeline from where the history stands to its next breakpoint (`previous`: the
  /// run whose locked steps may be reused — another stack's on a replay).
  package func run(previous: PipelineRun? = nil) async {
    let start = workspace.studio.steps.count
    guard follows(upTo: start) else {
      failure = .app("The history does not follow the pipeline: undo to a step it shares")
      return
    }
    await moving { [runner, pipeline] history, bundle, sink in
      try await runner.run(
        pipeline, on: history, bundle: bundle, from: start, previous: previous ?? self.lastRun,
        onEvent: sink)
    }
  }

  /// The user's « Continue » at the breakpoint: the step with the panel's values, then on to
  /// the next breakpoint; the pipeline keeps the values applied (R5).
  package func continueRun() async {
    guard canContinue, let index = stoppedAt, let panel = workspace.panel else { return }
    let params = panel.params
    pipeline.steps[index].recipe = Recipe(processID: panel.type.id, params: params)
    await moving { [runner, pipeline, lastRun] history, bundle, sink in
      try await runner.resume(
        pipeline, at: index, on: history, bundle: bundle, params: params, previous: lastRun,
        onEvent: sink)
    }
  }

  /// A manual Apply of `processID` with `params`: at the breakpoint of the same process it is
  /// that step done with these values; elsewhere a new `auto` step where the history put it.
  func applied(_ processID: String, params: ParamSet) {
    let index = workspace.studio.steps.count - 1
    guard index >= 0 else { return }
    let recipe = Recipe(processID: processID, params: params)
    if stoppedAt == index, pipeline.steps[index].recipe.processID == processID {
      pipeline.steps[index].recipe = recipe
      stoppedAt = nil
      return
    }
    pipeline.steps.insert(PipelineStep(recipe: recipe), at: min(index, pipeline.steps.count))
    if let stop = stoppedAt, stop >= index { stoppedAt = stop + 1 }
  }

  /// Whether the history's first `count` steps run the pipeline's processes in order.
  private func follows(upTo count: Int) -> Bool {
    let applied = workspace.studio.steps.map(\.processID)
    let planned = pipeline.steps.prefix(count).map(\.recipe.processID)
    return applied.count <= pipeline.steps.count && Array(applied) == Array(planned)
  }

  /// Runs `body` on the history, then shows the new head and loads the breakpoint's process.
  private func moving(
    _ body:
      @escaping (History, PipelineBundle, @escaping PipelineRunner.EventSink) async throws ->
      PipelineRunner.Outcome
  ) async {
    guard !isRunning else { return }
    isRunning = true
    failure = nil
    events = []
    progress = [:]
    defer { isRunning = false }
    let studio = workspace.studio
    let bundle = studio.session.bundle
    // Events come from the run's task or a batch tool's: kept under a lock, shown after the run;
    // a batch step's progress is shown as it goes.
    let log = OSAllocatedUnfairLock(initialState: [PipelineRunner.Event]())
    let sink: PipelineRunner.EventSink = { [weak self] event in
      log.withLock { $0.append(event) }
      if case .progress(let index, let fraction) = event {
        Task { @MainActor in self?.progress[index] = fraction }
      }
    }
    defer { events = log.withLock { $0 } }
    do {
      let outcome = try await studio.moving { try await body($0, bundle, sink) }
      lastRun = PipelineRun(history: studio.session.history, bundle: bundle)
      try workspace.headChanged()
      halted(outcome)
    } catch {
      failure = UserFacingError(error).message
      try? workspace.headChanged()
    }
  }

  private func halted(_ outcome: PipelineRunner.Outcome) {
    guard case .stopped(let index) = outcome else {
      stoppedAt = nil
      return
    }
    stoppedAt = index
    let recipe = pipeline.steps[index].recipe
    guard let type = workspace.registry.type(id: recipe.processID) else { return }
    workspace.choose(
      recipe.processID, params: ParamSet.loading(recipe.params, onto: type.schema).params)
  }
}
