internal import Foundation
internal import ProjectKit
package import StackKit

/// The Stacking stage's run and the Studio's stack.
extension ProjectWindowModel {
  /// The import the next run plans: every capture night of the project, with the overrides
  /// stored with the latest stack and then those of each import this session, merged (a later
  /// choice wins); `nil` without a night.
  func runRequest() throws -> ImportRequest? {
    let nights = sources.filter { $0.kind == .night }.map(\.path)
    guard !nights.isEmpty else { return nil }
    let base = try latestStackRequest() ?? ImportRequest(paths: nights)
    var request = imports.reduce(base) { $0.merging($1) }
    request.paths = nights
    return request
  }

  /// Run is offered: a capture night to stack and no run going.
  package var canRun: Bool {
    run?.isRunning != true && sources.contains { $0.kind == .night }
  }

  /// The target, as the project is named (`M31.astrostack` → `M31`).
  var targetName: String { folder()?.deletingPathExtension().lastPathComponent ?? "" }

  /// Runs preprocessing on the project's nights into `stacks/<run_id>/` of the package.
  ///
  /// The import is planned again (scan + calibration plan, the overrides as left), then StackKit
  /// runs it with the calibration choices the plan showed. A finished run becomes a stack with one
  /// image per bundle layer and the Studio opens it; a cancelled or failed one registers nothing
  /// and keeps its artifacts. One run at a time, in a saved project only (an untitled package
  /// moves on Save and is deleted on Close).
  package func startRun(mode: PreprocessRequest.Mode = .deepsky) {
    guard canRun else { return }
    guard let store = store(), let folder = folder() else {
      error = .projectClosed
      return
    }
    guard isSaved() else {
      error = .projectUnsaved
      return
    }
    let request: ImportRequest
    do {
      guard let planned = try runRequest() else { return }
      request = planned
    } catch {
      self.error = UserFacingError(error)
      return
    }
    let runID = Self.unusedRunID(runs.nextRunID, in: folder)
    let output = folder.appendingPathComponent("stacks/\(runID)", isDirectory: true)
    let work = runs.scratch.appendingPathComponent("run_\(runID)", isDirectory: true)
    let planning = services(store).planning
    let start = runs.run
    let model = RunViewModel(runID: runID, output: output)
    run = model
    refresh()
    model.start(
      {
        // The run re-plans the import silently: its own progress is the run's journal.
        let plan = try await planning(request) { _ in }
        var preprocess = PreprocessRequest(
          inventory: plan.inventory, output: output, work: work, runID: runID, mode: mode,
          library: plan.library)
        preprocess.settings.calibrationExcluded = request.calibExclude
        preprocess.settings.forceCalibration = request.forceCalibration
        return start(preprocess)
      },
      completion: { [weak self] outcome in
        await Self.remove(work)
        guard let self else { return }
        if case .success = outcome {
          await register(request: request, runID: runID)
        } else {
          refresh()
        }
      })
  }

  /// Cancels the running run; its finished masters stay in its folder.
  package func cancelRun() {
    run?.cancel()
  }

  /// Opens the latest stack in the Studio, off the main actor (bundle and FITS headers).
  package func openStudio() async {
    guard studio == nil, let folder = folder() else { return }
    do {
      guard let stack = try store()?.latestStack() else { return }
      let source = try await Self.openStack(
        folder.appendingPathComponent(stack.bundlePath), object: targetName)
      studio = studio ?? LegacyRunModel(source: source)
    } catch {
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

  /// Records a finished run as a stack of the nights it read, with its request as parameters
  /// and one image per layer in one transaction, and shows it in the Studio.
  ///
  /// The stack is opened first: a bundle the Studio cannot open is reported, not recorded.
  /// The package is read where it is now: a project renamed in the Finder after the run's last
  /// write still records its stack.
  private func register(request: ImportRequest, runID: String) async {
    do {
      guard let store = store(), let folder = folder() else {
        throw UserFacingError.projectClosed
      }
      let source = try await Self.openStack(
        folder.appendingPathComponent("stacks/\(runID)"), object: targetName)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let params = String(bytes: try encoder.encode(request), encoding: .utf8) ?? "{}"
      let read = sources.filter { request.paths.contains($0.path) }.map(\.id)
      try store.addStack(
        bundlePath: "stacks/\(runID)", sourceIDs: read, paramsJSON: params,
        imageRoles: source.layers.map(\.id))
      studio = LegacyRunModel(source: source)
      refresh()
      select(.studio)
    } catch {
      refresh()
      self.error = UserFacingError(error)
    }
  }

  /// The request stored with the latest stack, or `nil` without one.
  ///
  /// One that no longer decodes is an error the user sees, never a run without its overrides (R2).
  private func latestStackRequest() throws -> ImportRequest? {
    guard let stack = try store()?.latestStack() else { return nil }
    return try JSONDecoder().decode(ImportRequest.self, from: Data(stack.paramsJSON.utf8))
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
