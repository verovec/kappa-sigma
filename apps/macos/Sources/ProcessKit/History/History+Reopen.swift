package import Foundation
package import ImageKit

extension History {
  /// The history recorded for `directory`, on `original`.
  ///
  /// `<directory>.json` beside it gives the steps, undone steps and snapshots; the head is read
  /// from disk. A folder without a manifest is a fresh history. `schema` gives each process's
  /// schema, to read its stored values back; `movesPixels` says whether a step moved the pixels
  /// when its entry does not (a manifest written before card 0106: `ProcessRegistry.movesPixels`).
  package static func reopen(
    directory: URL, original: AstroImage, header: FITSHeader? = nil,
    movesPixels: (String, ParamSet) -> Bool = { _, _ in false },
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
      let params = ParamSet.loading(entry.params, onto: schema).params
      return Step(
        processID: entry.processID, params: params, file: entry.file, outputs: outputs,
        replaced: entry.replaced ?? [:],
        movesPixels: entry.movesPixels ?? movesPixels(entry.processID, params),
        branchHeads: entry.branchHeads ?? [:])
    }
    let versions = try (manifest.versions ?? []).map { entry in
      guard entry.base >= 0 else { throw HistoryError.unreadable("version \(entry.id) base") }
      guard (0...entry.steps.count).contains(entry.redo ?? 0) else {
        throw HistoryError.unreadable("version \(entry.id) redo")
      }
      return Version(
        id: entry.id, label: entry.label, base: entry.base, parent: entry.parent,
        steps: try entry.steps.map(step), redo: entry.redo ?? 0)
    }
    try history.load(
      steps: manifest.steps.map(step), undone: manifest.undone.map(step),
      snapshots: manifest.snapshots.map { Snapshot(name: $0.name, file: $0.file) },
      versions: versions, nextNumber: manifest.nextNumber,
      nextVersionNumber: manifest.nextVersion ?? versions.count + 1)
    return history
  }

  /// The manifest of the current state.
  var manifest: HistoryManifest {
    manifest(steps: steps, undone: undone, snapshots: snapshots, versions: versions)
  }

  /// The manifest of a state about to be: written before the history moves to it, so a failed
  /// write leaves the history as it was.
  func manifest(
    steps: [Step], undone: [Step], snapshots: [Snapshot], versions: [Version]
  ) -> HistoryManifest {
    func entry(_ step: Step) -> HistoryManifest.Entry {
      HistoryManifest.Entry(
        processID: step.processID, params: step.params.entries, file: step.file,
        outputs: Dictionary(uniqueKeysWithValues: step.outputs.map { ($0.key.rawValue, $0.value) }),
        replaced: step.replaced.isEmpty ? nil : step.replaced,
        movesPixels: step.movesPixels ? true : nil,
        branchHeads: step.branchHeads.isEmpty ? nil : step.branchHeads)
    }
    return HistoryManifest(
      version: HistoryManifest.version, nextNumber: nextStepNumber, steps: steps.map(entry),
      undone: undone.map(entry),
      snapshots: snapshots.map { HistoryManifest.Snapshot(name: $0.name, file: $0.file) },
      versions: versions.isEmpty
        ? nil
        : versions.map {
          HistoryManifest.Version(
            id: $0.id, label: $0.label, base: $0.base, parent: $0.parent,
            steps: $0.steps.map(entry), redo: $0.redo == 0 ? nil : $0.redo)
        },
      nextVersion: nextVersionNumber > 1 ? nextVersionNumber : nil)
  }

  func writeManifest() throws {
    try manifest.write(in: directory)
  }

  /// Writes the manifest of the state `steps`, `undone`, `snapshots`, `versions` (the current
  /// versions unless given).
  func writeManifest(
    steps: [Step], undone: [Step], snapshots: [Snapshot], versions: [Version]? = nil
  ) throws {
    try manifest(
      steps: steps, undone: undone, snapshots: snapshots, versions: versions ?? self.versions
    ).write(in: directory)
  }
}
