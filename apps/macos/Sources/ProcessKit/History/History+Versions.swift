internal import Foundation

// MARK: - Versions (card 0156)

extension History {
  /// A superseded tail: the steps from `base` as they were before a revise or a restore (the
  /// undone ones after them), kept with their files so nothing is lost (E25: « never lose »).
  package struct Version: Equatable, Sendable {
    /// Its id, never used before in this history.
    package let id: String
    /// What the user reads in the Versions menu.
    package let label: String
    /// The index of its first step: it replaces the steps from there.
    package let base: Int
    /// The file of step `base - 1` it was computed on, `nil` on the original: restored only
    /// on that same step.
    package let parent: String?
    /// The steps from `base`, oldest first.
    package let steps: [Step]
  }

  /// Revises from step `index`: the head goes back to the output of `index - 1` (the original
  /// for 0), `steps[index...]` and the undone steps become a version, then `body` applies the
  /// new steps.
  ///
  /// The previous output is read first: a failed read leaves the history as it was. When `body`
  /// throws before applying a step, the history is put back exactly (steps, undone, head,
  /// manifest) and `body`'s error is thrown; once it applied one, what it applied stays and so
  /// does the version (a replay that fails half-way keeps its steps).
  package func revise(
    from index: Int, label: String, _ body: (History) async throws -> Void
  ) async throws {
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    let previous = try image(file: index == 0 ? nil : steps[index - 1].file)
    let saved = (
      steps: steps, undone: undone, versions: versions, shown: shown, number: nextVersionNumber
    )
    let version = tail(from: index, label: label)
    try move(
      steps: Array(steps[..<index]), undone: [], versions: versions + [version], shown: previous)
    let applied = nextStepNumber
    do {
      try await body(self)
    } catch {
      if nextStepNumber == applied {
        // Best effort: the caller learns why the revise stopped, not why its undo did.
        nextVersionNumber = saved.number
        try? move(
          steps: saved.steps, undone: saved.undone, versions: saved.versions, shown: saved.shown)
      }
      throw error
    }
  }

  /// Puts version `id` back in place of the steps from its base: the replaced steps (and the
  /// undone ones) become a version of the same label, restoring it is the way back; only the
  /// new head is read from disk — nothing is recomputed.
  ///
  /// The version must sit on the very step it was computed on (`parent`): after the steps
  /// before it changed, it is out of reach.
  package func restore(version id: String) throws {
    guard let index = versions.firstIndex(where: { $0.id == id }) else {
      throw HistoryError.unknownVersion(id)
    }
    let version = versions[index]
    guard version.base <= steps.count, parentFile(of: version.base) == version.parent else {
      throw HistoryError.versionOutOfReach(id)
    }
    let restored = Array(steps[..<version.base]) + version.steps
    let head = try image(file: restored.last?.file)
    var kept = versions
    kept.remove(at: index)
    let replaced = tail(from: version.base, label: version.label)
    if !replaced.steps.isEmpty { kept.append(replaced) }
    try move(steps: restored, undone: [], versions: kept, shown: head)
  }

  /// Forgets version `id`: its files are no longer referenced, `save` removes them.
  package func dropVersion(_ id: String) throws {
    guard versions.contains(where: { $0.id == id }) else { throw HistoryError.unknownVersion(id) }
    try move(
      steps: steps, undone: undone, versions: versions.filter { $0.id != id }, shown: shown)
  }

  /// The steps from `base` then the undone ones, in the order they would apply, as a version.
  private func tail(from base: Int, label: String) -> Version {
    Version(
      id: mintVersionID(), label: label, base: base, parent: parentFile(of: base),
      steps: Array(steps[base...]) + undone.reversed())
  }

  /// The file of step `base - 1`, `nil` for the original.
  private func parentFile(of base: Int) -> String? {
    base == 0 ? nil : steps[base - 1].file
  }
}
