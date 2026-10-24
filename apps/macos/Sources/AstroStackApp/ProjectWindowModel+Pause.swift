internal import Foundation
internal import ProjectKit
internal import StackKit

/// Pause, Continue and Discard of a preprocessing run (card 0097). A paused run is a `paused`
/// stack row (its record and checkpoint) and its folder in `stacks/`; it survives closing the
/// project and is continued by the user only, never on launch.
extension ProjectWindowModel {
  /// Asks the running run to pause after its current lane.
  ///
  /// The rest of the queue is dropped when
  /// the run ends, paused or finished on its last lane (`ended`): the user asked to stop.
  package func pauseRun() {
    guard let run, run.canPause else { return }
    run.pause()
  }

  /// Continues the paused run `id`: the same run id, folder and record, its done lanes reused.
  package func continueRun(_ id: Int64) {
    guard !isStacking else { return }
    guard isSaved() else {
      error = .projectUnsaved
      return
    }
    guard let paused = pausedRuns.first(where: { $0.id == id }) else { return }
    let record: StackRecord
    do {
      record = try StackRecord(stack: paused)
    } catch {
      self.error = UserFacingError(error)
      return
    }
    // The frozen panel shows the values the continued run applies: the paused run's own (R2).
    knobs.load(record)
    queuedScopes = []
    queueActive = true
    launch(scope: record.scope, mode: record.mode, knobs: RunKnobs(record), resume: paused)
  }

  /// Discards the paused run `id`: its row, then its folder (the masters it kept).
  package func discardPausedRun(_ id: Int64) async {
    guard !isStacking, let store = store(), let folder = folder(),
      let paused = pausedRuns.first(where: { $0.id == id })
    else { return }
    do {
      try store.deletePausedStack(id: id)
    } catch {
      self.error = UserFacingError(error)
      return
    }
    await Self.remove(folder.appendingPathComponent(paused.bundlePath, isDirectory: true))
    refresh()
  }

  /// Records a run that paused.
  ///
  /// A new `paused` row, or the continued run's row with its new checkpoint. A pause that cannot
  /// be recorded is reported; its folder stays.
  func recordPause(
    _ record: StackRecord, runID: String, checkpoint: PreprocessCheckpoint,
    replacing paused: ProjectStack?
  ) {
    do {
      guard let store = store() else { throw UserFacingError.projectClosed }
      let row = try rowFields(record, runID: runID)
      let checkpointJSON = try Self.sortedJSON(checkpoint)
      if let paused {
        try store.updatePausedStack(
          id: paused.id, paramsJSON: row.params, checkpointJSON: checkpointJSON)
      } else {
        try store.addStack(
          bundlePath: "stacks/\(runID)", sourceIDs: row.sourceIDs, paramsJSON: row.params,
          object: record.scope?.object ?? "", scopeJSON: row.scope, status: .paused,
          checkpointJSON: checkpointJSON)
      }
      refresh()
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// What a stack row of `record` (run `runID`) stores: its params (the record with the user's
  /// hand), its scope and the sources it read — one derivation for finished and paused rows.
  func rowFields(_ record: StackRecord, runID: String) throws -> (
    params: String, scope: String?, sourceIDs: [Int64]
  ) {
    let read = sources.filter { record.request.paths.contains($0.path) }.map(\.id)
    return (
      try Self.sortedJSON(handed(record, runID: runID)), try record.scope.map(Self.sortedJSON),
      read
    )
  }

  /// `record` with the hand the user gave in run `runID` (cards 0069, 0096) on top of what a
  /// paused part of the same run already recorded.
  func handed(_ record: StackRecord, runID: String) -> StackRecord {
    var record = record
    guard let run, run.runID == runID else { return record }
    if run.wasReviewed {
      record.frameReview = (record.frameReview ?? [:]).merging(run.decisions) { $1 }
    }
    if !run.pins.isEmpty { record.referencePins = run.pins }
    return record
  }

  /// `value` as the JSON a stack row stores, keys sorted.
  static func sortedJSON(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(bytes: try encoder.encode(value), encoding: .utf8) ?? "{}"
  }
}
