internal import Foundation
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

  /// Run is offered: a capture night to stack, no run or queue going, and — once a scan lists
  /// the series — at least one checked set.
  package var canRun: Bool {
    !queueActive && run?.isRunning != true && sources.contains { $0.kind == .night }
      && (series.isEmpty || !series.scopes.isEmpty)
  }

  /// The `project_settings` key of the stack the Studio shows (card 0095).
  static let stackSettingKey = "workspace.stack"

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
  /// per bundle layer; the Studio opens the last stack of the queue. A cancelled or failed run
  /// registers nothing, keeps its artifacts and drops the rest of the queue. A saved project only
  /// (an untitled package moves on Save and is deleted on Close).
  ///
  /// The settings are the panel's edits (`knobs.patch`) on the preset of `mode`, the panel's own
  /// preset unless a mode is given for this run — read once here for the whole queue (the panel
  /// is frozen until it ends) and left as they are.
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
    launch(scope: scopes.first, mode: preset, patch: knobs.patch(for: preset))
  }

  /// Starts one run of `scope` (every light when `nil`) with `patch` on the preset of `mode`.
  private func launch(scope: RunScope?, mode: PreprocessRequest.Mode, patch: KnobPatch) {
    guard let store = store(), let folder = folder() else {
      endQueue()
      error = .projectClosed
      return
    }
    guard let (record, settings) = prepare(scope: scope, mode: mode, patch: patch) else {
      endQueue()
      return
    }
    // The run plans the same folders again: a Rescan still reading them only competes for disk.
    cancelScan()
    let runID = Self.unusedRunID(runs.nextRunID, in: folder)
    let output = folder.appendingPathComponent("stacks/\(runID)", isDirectory: true)
    let work = runs.scratch.appendingPathComponent("run_\(runID)", isDirectory: true)
    // The run re-plans the import silently: its own progress is the run's journal.
    let planning = ImportViewModel.silent(services(store).planning)
    let start = runs.run
    let model = RunViewModel(runID: runID, output: output)
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
        return start(
          PreprocessRequest(
            inventory: inventory, output: output, work: work, runID: runID, mode: record.mode,
            settings: settings, library: plan.library))
      },
      completion: { [weak self] outcome in
        await Self.remove(work)
        guard let self else { return }
        guard case .success = outcome else {
          endQueue()
          return
        }
        await register(record, runID: runID)
        if let next = queuedScopes.first, error == nil {
          queuedScopes.removeFirst()
          launch(scope: next, mode: mode, patch: patch)
        } else {
          endQueue()
        }
      })
  }

  /// The record and settings of a run of `scope` with `patch` on the preset of `mode`; `nil`
  /// (reported when it is an error) when nothing can run.
  private func prepare(scope: RunScope?, mode: PreprocessRequest.Mode, patch: KnobPatch) -> (
    StackRecord, PreprocessSettings
  )? {
    do {
      guard let request = try runRequest() else { return nil }
      let record = StackRecord(request: request, mode: mode, knobs: patch, scope: scope)
      return (record, try Self.runSettings(record))
    } catch {
      self.error = UserFacingError(error)
      return nil
    }
  }

  /// The queue is over (drained, cancelled or failed): Run is offered again; an error reported
  /// on the way stays shown (a refresh clears none).
  private func endQueue() {
    let reported = error
    queuedScopes = []
    queueActive = false
    refresh()
    if error == nil { error = reported }
  }

  /// The settings a run of `record` applies: its knobs on its preset, with the calibration
  /// choices of its import, as the panel and the Import sheet showed them.
  static func runSettings(_ record: StackRecord) throws -> PreprocessSettings {
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
    let chosen = selectedStackID
    do {
      guard let stack = selectedStack else { return }
      let source = try await Self.openStack(
        folder.appendingPathComponent(stack.bundlePath), object: studioObject(stack.object))
      guard chosen == selectedStackID else { return }
      studio = studio ?? LegacyRunModel(source: source)
    } catch {
      guard chosen == selectedStackID else { return }
      self.error = UserFacingError(error)
    }
  }

  @concurrent
  private nonisolated static func openStack(_ folder: URL, object: String) async throws
    -> LegacyRunSource
  {
    try LegacyRunSource(stack: folder, object: object)
  }

  /// Siril's work files: tens of GB per night, never reused (job-scratch lesson).
  @concurrent
  private nonisolated static func remove(_ work: URL) async {
    try? FileManager.default.removeItem(at: work)
  }

  /// Records a finished run as a stack of the nights it read, with its request as parameters,
  /// its object and scope, and one image per layer in one transaction; the last stack of the
  /// queue is chosen and shown in the Studio.
  ///
  /// The stack is opened first: a bundle the Studio cannot open is reported, not recorded.
  /// The package is read where it is now: a project renamed in the Finder after the run's last
  /// write still records its stack.
  private func register(_ record: StackRecord, runID: String) async {
    do {
      guard let store = store(), let folder = folder() else {
        throw UserFacingError.projectClosed
      }
      let object = record.scope?.object ?? ""
      let source = try await Self.openStack(
        folder.appendingPathComponent("stacks/\(runID)"), object: studioObject(object))
      var record = record
      // The hand the user gave at the review travels with the stack (card 0069).
      if let run, run.runID == runID, run.wasReviewed { record.frameReview = run.decisions }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let params = String(bytes: try encoder.encode(record), encoding: .utf8) ?? "{}"
      let scopeJSON = try record.scope.map {
        String(bytes: try encoder.encode($0), encoding: .utf8) ?? "{}"
      }
      let read = sources.filter { record.request.paths.contains($0.path) }.map(\.id)
      let stack = try store.addStack(
        bundlePath: "stacks/\(runID)", sourceIDs: read, paramsJSON: params,
        imageRoles: source.layers.map(\.id), object: object, scopeJSON: scopeJSON)
      knobs.clearIgnored()
      refresh()
      selectStack(stack.id)
      if queuedScopes.isEmpty {
        studio = LegacyRunModel(source: source)
        select(.studio)
      }
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
