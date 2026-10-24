internal import Foundation
internal import ProcessKit
internal import ProjectKit
package import StackKit

/// The Stacking stage's runs and the Studio's stack.
extension ProjectWindowModel {
  /// The import the next run plans: every capture night of the project, with the overrides
  /// stored with the latest stack and then those of each import this session, merged (a later
  /// choice wins); `nil` without a night.
  func runRequest() throws -> ImportRequest? {
    let nights = sources.filter { $0.kind == .night }.map(\.path)
    guard !nights.isEmpty else { return nil }
    let base = try latestStackRecord()?.request ?? ImportRequest(paths: nights)
    var request = imports.reduce(base) { $0.merging($1) }
    request.paths = nights
    return request
  }

  /// Run is offered.
  ///
  /// A capture night to stack, no run or queue going, and — once a scan lists the series — at
  /// least one checked set. Without a scan, a project whose stacks show several objects waits for
  /// one (`needsSeries`): a run of every light would only fail after the plan.
  /// While every night is rescanned after Add a night, Run waits for the plan (card 0100).
  package var canRun: Bool {
    !isStacking && !awaitsRescan && sources.contains { $0.kind == .night }
      && (series.isEmpty ? !needsSeries : !series.scopes.isEmpty)
  }

  /// A run or a queue is going: the knobs, the series and the review toggles are frozen until
  /// it ends, between two queued runs too (R2: the values shown are the values applied).
  package var isStacking: Bool { queueActive || run?.isRunning == true }

  /// No scan lists the series yet, and the recorded stacks name several objects (card 0095).
  package var needsSeries: Bool {
    series.isEmpty && Set(stacks.map(\.object).filter { !$0.isEmpty }).count > 1
  }

  /// The `project_settings` key of the stack the Studio shows (card 0095).
  nonisolated static let stackSettingKey = "workspace.stack"

  /// The target, as the project is named (`M31.astrostack` → `M31`).
  var targetName: String { folder()?.deletingPathExtension().lastPathComponent ?? "" }

  /// What a stack's Studio is named after: its object, else the project.
  func studioObject(_ object: String) -> String {
    object.isEmpty ? targetName : object
  }

  /// Runs preprocessing on the project's nights into `stacks/<run_id>/` of the package: one run
  /// per object with a checked series (card 0095), in the table's order, one after the other —
  /// or one run of every light when no scan listed the series.
  ///
  /// Each run plans the import again (scan + calibration plan, the overrides as left), scopes the
  /// inventory to its object's light sets (every calibration set travels), then StackKit runs it
  /// with the calibration choices the plan showed. A finished run becomes a stack with one image
  /// per bundle layer; when the queue ends (drained, failed or cancelled) the Studio loads the last
  /// stack it recorded. A cancelled or failed run
  /// registers nothing, keeps its artifacts and drops the rest of the queue. A saved project only
  /// (an untitled package moves on Save and is deleted on Close).
  ///
  /// The settings are the panel's edits (`knobs.patch`) on the preset of `mode`, the panel's own
  /// preset unless a mode is given for this run, with its lane values and processing for each run
  /// that splits (card 0121) — read once here for the whole queue (the panel is frozen until it
  /// ends) and left as they are.
  package func startRun(mode: PreprocessRequest.Mode? = nil) {
    guard canRun else { return }
    guard isSaved() else {
      error = .projectUnsaved
      return
    }
    let scopes = series.scopes
    let preset = mode ?? knobs.mode
    queuedScopes = Array(scopes.dropFirst())
    queueActive = true
    launch(scope: scopes.first, mode: preset, knobs: knobs.runKnobs(for: preset))
  }

  /// Starts one run of `scope` (every light when `nil`) with `knobs` on the preset of `mode` — or,
  /// given a paused run's row (card 0097), continues it: its own record, run id and folder, the
  /// lanes its checkpoint matches reused.
  func launch(
    scope: RunScope?, mode: PreprocessRequest.Mode, knobs: RunKnobs, resume: ProjectStack? = nil
  ) {
    guard let store = store(), let folder = folder() else {
      endQueue(drained: false)
      error = .projectClosed
      return
    }
    guard let (record, settings) = prepare(scope: scope, mode: mode, knobs: knobs, resume: resume)
    else {
      endQueue(drained: false)
      return
    }
    let scope = resume == nil ? scope : record.scope
    // The run plans the same folders again: a Rescan still reading them only competes for disk.
    cancelScan()
    let runID =
      resume.map { URL(fileURLWithPath: $0.bundlePath).lastPathComponent }
      ?? Self.unusedRunID(runs.nextRunID, in: folder)
    let output = folder.appendingPathComponent("stacks/\(runID)", isDirectory: true)
    let scratch = runs.scratch
    let work = scratch.appendingPathComponent("run_\(runID)", isDirectory: true)
    let room = runs.room
    // The run re-plans the import silently: its own progress is the run's journal.
    let planning = ImportViewModel.silent(services(store).planning)
    let start = runs.run
    let model = RunViewModel(runID: runID, output: output)
    let gate = model.gate
    run = model
    refresh()
    model.start(
      {
        let plan = try await planning(record.request)
        // A scan that moved since the series were chosen is refused, never stacked in part.
        if let scope {
          let unlisted = scope.unlistedSets(in: plan.inventory)
          guard unlisted.isEmpty else { throw PreprocessError.scopeOutdated(unlisted) }
        }
        let inventory = scope.map { plan.inventory.scoped($0) } ?? plan.inventory
        // Refused before Siril starts, never left to fail mid-run on a full disk (card 0098).
        try Self.checkScratch(inventory, settings: settings, folder: scratch, room: room)
        var request = PreprocessRequest(
          inventory: inventory, output: output, work: work, runID: runID, mode: record.mode,
          settings: settings, library: plan.library)
        request.pause = gate
        request.resuming = resume != nil
        // Validated by `prepare`: lane knobs only, each accepted.
        for (lane, patch) in record.laneKnobs { try request.overrideLane(lane, with: patch) }
        return start(request)
      },
      completion: { [weak self] outcome in
        await Self.remove(work)
        await self?.ended(
          outcome, record: record, runID: runID, resume: resume, mode: mode, knobs: knobs)
      })
  }

  /// A run of the queue ended: a finished run is registered (a continued one completes its
  /// paused row) and the next scope starts; a paused one is recorded; any other end stops the
  /// queue.
  private func ended(
    _ outcome: Result<PreprocessResult, any Error>, record: StackRecord, runID: String,
    resume: ProjectStack?, mode: PreprocessRequest.Mode, knobs: RunKnobs
  ) async {
    guard case .success = outcome else {
      if case .failure(let failure) = outcome, let paused = failure as? RunPaused {
        recordPause(record, runID: runID, checkpoint: paused.checkpoint, replacing: resume)
      } else if resume == nil, let run, run.runID == runID {
        // Finished masters stay (README); a folder with none would only pile up `_2`, `_3`. A
        // resumed run's folder is its paused stack's checkpoint: never removed here.
        await StackLeftovers.removeUnfinished(run.output)
      }
      endQueue(drained: false)
      return
    }
    await register(record, runID: runID, completing: resume?.id)
    // A Pause asked during the run's last lane finds nothing left to pause in it: the queue stops
    // here instead, as asked, and its next scopes are run again with Run.
    if let next = queuedScopes.first, error == nil, run?.pauseRequested != true {
      queuedScopes.removeFirst()
      launch(scope: next, mode: mode, knobs: knobs)
    } else {
      endQueue(drained: error == nil)
    }
  }

  /// The record and settings of a run of `scope` with `knobs` on the preset of `mode` — its lane
  /// values and processing only when the scope splits; `nil` (reported when it is an error) when
  /// nothing can run.
  private func prepare(
    scope: RunScope?, mode: PreprocessRequest.Mode, knobs: RunKnobs, resume: ProjectStack?
  ) -> (StackRecord, PreprocessSettings)? {
    do {
      if let resume {
        let record = try StackRecord(stack: resume)
        return (record, try Self.runSettings(record))
      }
      guard let request = try runRequest() else { return nil }
      let applied = scope.map(series.splits) == true ? knobs : knobs.unsplit
      var record = StackRecord(request: request, mode: mode, knobs: applied.patch, scope: scope)
      record.laneKnobs = applied.lanes
      record.processing = applied.processing
      return (record, try Self.runSettings(record))
    } catch {
      self.error = UserFacingError(error)
      return nil
    }
  }

  /// The queue is over (drained, cancelled or failed): Run is offered again, its stacks are
  /// listed and the last one it recorded is chosen and loaded in the Studio — shown only when
  /// the queue `drained`, so a failed run stays in view; an error reported on the way stays
  /// shown (a refresh clears none).
  func endQueue(drained: Bool) {
    let reported = error
    queuedScopes = []
    queueActive = false
    refresh()
    listLeftoverStacks()
    if let recorded = queueRecorded {
      queueRecorded = nil
      selectStack(recorded.stack.id)
      // A choice refused (the project closed meanwhile) loads nothing the picker does not name.
      if selectedStackID == recorded.stack.id {
        studio = LegacyRunModel(source: recorded.source)
        showWorkspace(of: recorded.stack, source: recorded.source)
        if drained { select(.studio) }
      }
    }
    if error == nil { error = reported }
  }

  /// The settings a run of `record` applies: its knobs on its preset, with the calibration
  /// choices of its import, as the panel and the Import sheet showed them; a lane value the
  /// schema refuses for a lane (card 0121) throws before anything runs.
  static func runSettings(_ record: StackRecord) throws -> PreprocessSettings {
    for patch in record.laneKnobs.values { try KnobSchema.validateLane(patch) }
    var settings = try KnobSchema.apply(record.knobs, to: .preset(record.mode))
    settings.calibrationExcluded = record.request.calibExclude
    settings.forceCalibration = record.request.forceCalibration
    return settings
  }

  /// Cancels the running run and the rest of the queue; its finished masters stay in its folder.
  package func cancelRun() {
    queuedScopes = []
    run?.cancel()
  }

  /// Opens the chosen stack (else the latest) in the Studio, off the main actor (bundle and FITS
  /// headers); a choice made meanwhile wins over the stack this call opened.
  package func openStudio() async {
    guard studio == nil, let folder = folder() else { return }
    guard let stack = selectedStack else { return }
    do {
      let source = try await Self.openStack(
        folder.appendingPathComponent(stack.bundlePath), object: studioObject(stack.object))
      guard stack.id == selectedStack?.id else { return }
      studio = studio ?? LegacyRunModel(source: source)
      showWorkspace(of: stack, source: source)
    } catch {
      guard stack.id == selectedStack?.id else { return }
      self.error = UserFacingError(error)
    }
  }

  /// Loads the Studio's working image of `stack` (the one the Studio shows) in a task the
  /// window owns, never the view's (its pane changes while the layers load); another stack
  /// replaces the one shown, the same one is kept.
  func showWorkspace(of stack: ProjectStack, source: LegacyRunSource) {
    guard workspaceStackID != stack.id, let folder = folder() else { return }
    dropWorkspace()
    workspaceStackID = stack.id
    let (stackID, bundlePath) = (stack.id, stack.bundlePath)
    workspaceTask = Task { [weak self] in
      do {
        try await self?.openWorkspace(
          source, stackID: stackID, folder: folder, bundlePath: bundlePath)
      } catch is CancellationError {
        return
      } catch {
        // Not loaded: the same stack may be tried again (showing the Studio retries it); a
        // stack dropped meanwhile reports nothing.
        guard self?.workspaceStackID == stackID else { return }
        self?.workspaceStackID = nil
        self?.pendingReplay = nil
        self?.error = UserFacingError(error)
      }
    }
  }

  /// Opens the workspace of the stack the Studio shows when none is loaded or loading (a failed
  /// load retried when the Studio is shown again).
  package func retryWorkspace() {
    guard workspace == nil, workspaceStackID == nil, let studio, let folder = folder() else {
      return
    }
    // The stack whose layers the Studio shows, never another one the selection now names.
    let shown = studio.source.folder.standardizedFileURL
    guard
      let stack = stacks.first(where: {
        folder.appendingPathComponent($0.bundlePath).standardizedFileURL == shown
      })
    else { return }
    showWorkspace(of: stack, source: studio.source)
  }

  /// The profile every night of stack `stackID` kept at import (a night without one counts),
  /// whose channel combination is step 0 of a fresh history; `nil` when they differ.
  func keptProfile(of stackID: Int64) -> Profile? {
    guard let store = store(), let stack = stacks.first(where: { $0.id == stackID }) else {
      return nil
    }
    let stackSources = sources.filter { stack.sourceIDs.contains($0.id) }
    guard let id = Self.agreedProfileID(stackSources) else { return nil }
    return ImportViewModel.profiles(store: store).profiles.first { $0.id == id }
  }

  /// The workspace of another stack, or none: its load stops, its undo actions go.
  func dropWorkspace() {
    workspaceTask?.cancel()
    workspaceTask = nil
    workspace?.retire()
    workspace = nil
    workspaceStackID = nil
    dropExport()
  }

  /// The Studio's working image of stack `stackID`: its layers read off the main actor, its
  /// history opened (step 0 = the channel combination of the kept profile, else the defaults).
  func openWorkspace(
    _ source: LegacyRunSource, stackID: Int64, folder: URL, bundlePath: String
  ) async throws {
    guard let store = store() else {
      if workspaceStackID == stackID { workspaceStackID = nil }
      return
    }
    let (bundle, roles, header) = try await StudioBundle.load(source)
    let combination = keptProfile(of: stackID)?.steps
      .first { $0.recipe.processID == ChannelCombinationProcess.id }
      .map { ParamSet.loading($0.recipe.params, onto: ChannelCombinationProcess.schema).params }
    try Task.checkCancellation()
    let studio = try StudioModel(
      store: store, stackID: stackID, packageFolder: folder,
      stackFolder: folder.appendingPathComponent(bundlePath), bundle: bundle, header: header,
      combination: combination)
    // Host tools work outside the document package: a crash never leaves files inside it.
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AstroStack/Work", isDirectory: true)
    // Background extraction is always offered: each engine names its own missing tool (0092).
    var tools = StudioTool.standard(scratch: scratch)
    tools[BackgroundExtractionProcess.id] = BackgroundExtractionTool.live(scratch: scratch)
    let workspace = try StudioWorkspaceModel(studio: studio, base: roles, tools: tools)
    // An undo from another stage brings the Studio into view before moving its history.
    workspace.reveal = { [weak self] in self?.select(.studio) }
    workspace.pipeline = try sidebar(of: workspace, stackID: stackID, store: store, roles: roles)
    self.workspace = workspace
    markOpened(stackID)
    showExport(of: studio, stackID: stackID, folder: folder)
    // The Studio's stage state follows; an error the window shows stays (a refresh clears it).
    let reported = error
    refresh()
    if error == nil { error = reported }
    await replayIfPending(on: stackID)
  }

  @concurrent
  private nonisolated static func openStack(_ folder: URL, object: String) async throws
    -> LegacyRunSource
  {
    try LegacyRunSource(stack: folder, object: object)
  }

  /// Siril's work files: tens of GB per night, never reused (job-scratch lesson).
  @concurrent
  nonisolated static func remove(_ work: URL) async {
    try? FileManager.default.removeItem(at: work)
  }

  /// Records a finished run as a stack of the nights it read, with its request as parameters,
  /// its object and scope, and one image per layer in one transaction; kept as the queue's last
  /// stack, chosen and loaded when the queue ends.
  ///
  /// The stack is opened first: a bundle the Studio cannot open is reported, not recorded. Once
  /// its row is written, its folder is trimmed to what the bundle reads (card 0114). The package
  /// is read where it is now: a project renamed in the Finder after the run's last write still
  /// records its stack. A continued run (card 0097) completes its paused row.
  private func register(_ record: StackRecord, runID: String, completing paused: Int64?) async {
    do {
      guard let store = store(), let folder = folder() else {
        throw UserFacingError.projectClosed
      }
      let object = record.scope?.object ?? ""
      let source = try await Self.openStack(
        folder.appendingPathComponent("stacks/\(runID)"), object: studioObject(object))
      let row = try rowFields(record, runID: runID)
      let roles = source.layers.map(\.id)
      let stack =
        try paused.map {
          try store.completeStack(id: $0, paramsJSON: row.params, imageRoles: roles)
        }
        ?? store.addStack(
          bundlePath: "stacks/\(runID)", sourceIDs: row.sourceIDs, paramsJSON: row.params,
          imageRoles: roles, object: object, scopeJSON: row.scope)
      await trimStack(folder.appendingPathComponent("stacks/\(runID)"), bundle: source.bundle)
      knobs.clearIgnored()
      // Shown when the queue ends, whether it drains, fails or is cancelled (`endQueue`).
      queueRecorded = (stack, source)
    } catch {
      queuedScopes = []
      refresh()
      self.error = UserFacingError(error)
    }
  }

  /// The record of the latest stack, or `nil` without one.
  ///
  /// One that no longer decodes is an error the user sees, never a run without its overrides (R2).
  func latestStackRecord() throws -> StackRecord? {
    try store()?.latestStack().map(StackRecord.init(stack:))
  }

  /// `runID`, or `runID_2`, `_3`… when a stack folder of that name exists (two runs in one
  /// second, the repeated hour of a DST change).
  static func unusedRunID(_ runID: String, in folder: URL) -> String {
    let stacks = folder.appendingPathComponent("stacks")
    var candidate = runID
    var suffix = 1
    while FileManager.default.fileExists(atPath: stacks.appendingPathComponent(candidate).path) {
      suffix += 1
      candidate = "\(runID)_\(suffix)"
    }
    return candidate
  }
}
