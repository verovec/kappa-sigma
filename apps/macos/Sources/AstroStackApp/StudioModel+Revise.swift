internal import Foundation
package import ProcessKit

// MARK: - Revising an applied step (card 0157)

extension StudioModel {
  /// Re-applies applied step `index` with `params`, then the steps after it as they recorded.
  ///
  /// The replay stops before the first host-tool step: those wait in the pipeline column for
  /// ▶ Run. The chain it replaces is kept as a history version (0156): nothing is lost.
  ///
  /// A host-tool step `index` runs `tool` (its Apply's), refused before anything moves when the
  /// caller has none. A recipe has no mask: a masked step replays unmasked (as `replayMain`).
  /// Returns the number of steps now applied.
  @discardableResult
  package func reviseStep(
    _ index: Int, params: ParamSet, tool: PipelineRunner.BatchProcess? = nil,
    onProgress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> Int {
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    let processID = steps[index].processID
    let isTool = runsTool(processID, params)
    if isTool, tool == nil { throw PipelineError.toolMissing(processID) }
    var recipes = steps.map {
      PipelineStep(recipe: Recipe(processID: $0.processID, params: $0.params))
    }
    recipes[index] = PipelineStep(recipe: Recipe(processID: processID, params: params))
    // The replay stops before the first host tool after `index`.
    let end =
      steps.indices.dropFirst(index + 1).first { runsTool(steps[$0].processID, steps[$0].params) }
      ?? recipes.count
    let replayed = Array(recipes[..<end])
    let session = session
    // Made before anything moves: a runner that cannot start leaves the history as it was.
    let runner = try replayRunner()
    let label = Self.versionLabels(base: index).before
    try await moving { history in
      try await history.revise(from: index, label: label) { history in
        if isTool, let tool {
          try await tool.record(
            processID, params: params, in: history, bundle: session.bundle,
            onProgress: onProgress)
          try await replay(replayed, from: index + 1, on: history, with: runner)
        } else {
          try await replay(replayed, from: index, on: history, with: runner)
        }
      }
    }
    return steps.count
  }

  /// Puts history version `id` back in place of the steps from its base: nothing is recomputed.
  ///
  /// A revise's undo or redo. Returns the id of the version the replaced steps became.
  package func restoreVersion(_ id: String) throws -> String? {
    defer { mirror() }
    let history = session.history
    guard let version = history.versions.first(where: { $0.id == id }) else {
      throw HistoryError.unknownVersion(id)
    }
    // The chain put aside is the other one: before the revise ↔ revised.
    let labels = Self.versionLabels(base: version.base)
    let replaced = try history.restore(
      version: id, replacedLabel: version.label == labels.before ? labels.revised : labels.before)
    cleanUp()
    return replaced
  }

  /// The labels of the two chains of a revise of step `base`, as the Versions menu reads them
  /// (in the language of the day: a label is a recorded name, like a snapshot's).
  static func versionLabels(base: Int) -> (before: String, revised: String) {
    (
      String(localized: .app("Before revising step \(base + 1)")),
      String(localized: .app("Revised step \(base + 1)"))
    )
  }

  /// Whether `processID` with `params` runs a host tool (a step the registry cannot render, such
  /// as StarNet's, counts as one): the one rule of the revise, its refusal and `replayMain`.
  package func runsTool(_ processID: String, _ params: ParamSet) -> Bool {
    session.registry.type(id: processID)?.runsTool(params) ?? true
  }
}
