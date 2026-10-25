internal import AppKit
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
    /// Applied, but a branch it read has moved since (card 0119): Replay runs it again.
    case stale
    /// The run halted before it; its process is in the panel.
    case current
    /// Not reached yet.
    case next
  }

  /// The pipeline shown (edited by the user's toggles, Continue values and manual Applies).
  package internal(set) var pipeline: Pipeline
  /// The breakpoint the run halted at, if any.
  package internal(set) var stoppedAt: Int?
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

  /// Whether Continue can run: halted at a breakpoint still on (the history holds exactly the
  /// steps before it) whose process the panel shows.
  package var canContinue: Bool {
    guard let index = stoppedAt, pipeline.steps.indices.contains(index),
      pipeline.steps[index].mode == .stop, workspace.studio.steps.count == index
    else { return false }
    return workspace.panel?.type.id == pipeline.steps[index].recipe.processID
  }

  /// Where step `index` stands.
  package func status(of index: Int) -> Status {
    if index < workspace.studio.steps.count {
      return index >= (workspace.studio.staleFrom ?? .max) ? .stale : .done
    }
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

  /// Names the pipeline `name` (saved under it); where the run stands is kept.
  func rename(_ name: String) {
    pipeline.name = name
  }

  /// Replaces the pipeline (loaded or replayed), with what its loading reported.
  package func show(_ pipeline: Pipeline, warnings: [String] = []) {
    self.pipeline = pipeline
    self.warnings = warnings
    stoppedAt = nil
  }

  /// Runs the pipeline from where the history stands to its next breakpoint.
  ///
  /// `previous` is another stack's run whose locked steps may be reused (a replay; the runner
  /// reuses one only for the same input). On this stack's own history nothing is reused: the
  /// last run is that very history, never a copy of it. The steps it adds are undone together on
  /// `undoManager`, the breakpoint with them.
  ///
  /// `before` is the column a ⌘Z puts back, as it is now unless given (a replay's, before it
  /// replaced the pipeline).
  package func run(
    previous: PipelineRun? = nil, undoManager: UndoManager? = nil, before: Mark? = nil
  ) async {
    let start = workspace.studio.steps.count
    guard follows(upTo: start) else {
      failure = .app("The history does not follow the pipeline: undo to a step it shares")
      return
    }
    await moving(on: undoManager, mark: before ?? mark()) { [runner, pipeline] in
      try await runner.run(
        pipeline, on: $0, bundle: $1, from: start, previous: previous, onEvent: $2)
    }
  }

  /// The user's « Continue » at the breakpoint: the step with the panel's values, then on to
  /// the next breakpoint; the pipeline keeps the values applied (R5), undone on `undoManager`
  /// with the breakpoint and the values it had.
  package func continueRun(undoManager: UndoManager? = nil) async {
    // Continue applies to the combined image: from a branch, the first press shows it there.
    guard workspace.selection == .main else {
      workspace.select(.main)
      return
    }
    // Read before the commit, whose value change ends the suspension: on a new head the values
    // are shown first, as Apply does, never applied unseen (R2).
    let previews = workspace.isPreviewSuspended
    // A value typed and not confirmed is committed first: Continue never applies an older one.
    NSApp?.keyWindow?.makeFirstResponder(nil)
    guard canContinue, let index = stoppedAt, let panel = workspace.panel else { return }
    if previews {
      workspace.resumePreview()
      return
    }
    let params = panel.params
    let before = mark(keeping: [index])
    let applied = await moving(on: undoManager, mark: before) { [runner, pipeline] in
      try await runner.resume(
        pipeline, at: index, on: $0, bundle: $1, params: params, onEvent: $2)
    }
    // Recorded once applied: a refused Continue leaves the recipe as it was.
    if applied, workspace.studio.steps.count > index {
      pipeline.steps[index].recipe = Recipe(processID: panel.type.id, params: params)
    }
  }

  /// A manual Apply of `processID` with `params` (`masked`: under a mask).
  ///
  /// Where the pipeline plans the same process next, it is that step done with these values;
  /// elsewhere a new `auto` step where the history put it. A recipe has no mask: a masked step
  /// is recorded with a warning that a replay applies it to the whole image.
  func applied(_ processID: String, params: ParamSet, masked: Bool = false) {
    let index = workspace.studio.steps.count - 1
    guard index >= 0 else { return }
    let recipe = Recipe(processID: processID, params: params)
    if masked {
      warnings.append(
        "step \(index + 1) (\(processID)) was applied under a mask; "
          + "the pipeline replays it unmasked")
    }
    if pipeline.steps.indices.contains(index), pipeline.steps[index].recipe.processID == processID {
      pipeline.steps[index].recipe = recipe
      if stoppedAt == index { stoppedAt = nil }
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

  /// Runs `body` on the history, then shows the new head and loads the breakpoint's process;
  /// whether it ran without failing.
  ///
  /// The steps added are registered on `undoManager` as one move, which puts the column back at
  /// `mark`.
  @discardableResult
  private func moving(
    on undoManager: UndoManager?, mark: Mark,
    _ body:
      @escaping (History, PipelineBundle, @escaping PipelineRunner.EventSink) async throws ->
      PipelineRunner.Outcome
  ) async -> Bool {
    // A replay of the stale steps rewrites the same history: a run waits for it (card 0119).
    guard !isRunning, !workspace.isReplaying else { return false }
    // A run applies to the combined image: it is shown first, its panel what Continue applies.
    workspace.select(.main)
    // A host tool's Apply records on the head it started from: a run waits for it (card 0092).
    guard workspace.toolTask == nil else {
      failure = .app("A tool is already running: wait for it, or stop it.")
      return false
    }
    isRunning = true
    failure = nil
    events = []
    progress = [:]
    defer { isRunning = false }
    let studio = workspace.studio
    let bundle = studio.session.bundle
    let before = studio.steps.count
    // Even a run that stops on a failure keeps the steps it applied: they are undoable too.
    defer { StudioUndo.recordRun(workspace, from: before, mark: mark, on: undoManager) }
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
      return true
    } catch {
      failure = UserFacingError(error).message
      try? workspace.headChanged()
      return false
    }
  }

  private func halted(_ outcome: PipelineRunner.Outcome) {
    guard case .stopped(let index) = outcome else {
      stoppedAt = nil
      return
    }
    halt(at: index)
  }
}
