package import Foundation
package import ImageKit

extension History {
  /// The history recorded for `directory`, on `original`.
  ///
  /// `<directory>.json` beside it gives the steps, undone steps and snapshots; the head is read
  /// from disk. A folder without a manifest is a fresh history. `schema` gives each process's
  /// schema, to read its stored values back.
  package static func reopen(
    directory: URL, original: AstroImage, header: FITSHeader? = nil,
    schema: (String) -> ParamSchema?
  ) throws -> History {
    let history = try History(directory: directory, original: original, header: header)
    guard let manifest = try HistoryManifest.read(in: directory) else { return history }
    func step(_ entry: HistoryManifest.Entry) throws -> Step {
      guard let schema = schema(entry.processID) else {
        throw HistoryError.unreadable("unknown process \(entry.processID)")
      }
      var outputs: [LayerRole: String] = [:]
      for (role, file) in entry.outputs {
        guard let role = LayerRole(rawValue: role) else {
          throw HistoryError.unreadable("unknown layer role \(role)")
        }
        outputs[role] = file
      }
      return Step(
        processID: entry.processID,
        params: ParamSet.loading(entry.params, onto: schema).params, file: entry.file,
        outputs: outputs)
    }
    try history.restore(
      steps: manifest.steps.map(step), undone: manifest.undone.map(step),
      snapshots: manifest.snapshots.map { Snapshot(name: $0.name, file: $0.file) },
      nextNumber: manifest.nextNumber)
    return history
  }

  /// The manifest of the current state.
  var manifest: HistoryManifest {
    manifest(steps: steps, undone: undone, snapshots: snapshots)
  }

  /// The manifest of a state about to be: written before the history moves to it, so a failed
  /// write leaves the history as it was.
  func manifest(steps: [Step], undone: [Step], snapshots: [Snapshot]) -> HistoryManifest {
    func entry(_ step: Step) -> HistoryManifest.Entry {
      HistoryManifest.Entry(
        processID: step.processID, params: step.params.entries, file: step.file,
        outputs: Dictionary(uniqueKeysWithValues: step.outputs.map { ($0.key.rawValue, $0.value) }))
    }
    return HistoryManifest(
      version: HistoryManifest.version, nextNumber: nextStepNumber, steps: steps.map(entry),
      undone: undone.map(entry),
      snapshots: snapshots.map { HistoryManifest.Snapshot(name: $0.name, file: $0.file) })
  }

  func writeManifest() throws {
    try manifest.write(in: directory)
  }

  /// Writes the manifest of the state `steps`, `undone`, `snapshots`.
  func writeManifest(steps: [Step], undone: [Step], snapshots: [Snapshot]) throws {
    try manifest(steps: steps, undone: undone, snapshots: snapshots).write(in: directory)
  }
}
