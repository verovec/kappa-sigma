internal import Foundation
package import ImageKit
package import ProcessKit

// MARK: - Revising an applied step (card 0157)

extension StudioModel {
  /// Re-applies applied step `index` with `params`, then the steps after it as they recorded.
  ///
  /// The replay stops before the first host-tool step: those wait in the pipeline column for
  /// ▶ Run. The chain it replaces is kept as a history version (0156): nothing is lost.
  ///
  /// A host-tool step `index` runs `tool` (its Apply's), refused before anything moves when the
  /// caller has none. Every masked GPU step, `index` included, replays under its recorded mask
  /// (card 0160; a host-tool step is never masked); a crop, turn or flip `index` with a masked
  /// step after it is refused before anything moves (`PipelineError.maskMoved`).
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
    var recipes = replayRecipes
    recipes[index] = PipelineStep(recipe: Recipe(processID: processID, params: params))
    // The replay stops before the first host tool after `index` (the chain preview's rule).
    let end = session.toolStep(from: index + 1, revising: index, params: params) ?? recipes.count
    try refuseMovedMask(index, params: params, until: end)
    let replayed = Array(recipes[..<end])
    let session = session
    // Made before anything moves: a runner that cannot start leaves the history as it was.
    let runner = try replayRunner()
    let masks = try replayMasks(index..<end)
    let label = Self.versionLabels(base: index).before
    try await moving { history in
      try await history.revise(from: index, label: label) { history in
        if isTool, let tool {
          try await tool.record(
            processID, params: params, in: history, bundle: session.bundle,
            onProgress: onProgress)
          try await replay(replayed, from: index + 1, on: history, with: runner, masks: masks)
        } else {
          try await replay(replayed, from: index, on: history, with: runner, masks: masks)
        }
      }
    }
    return steps.count
  }

  /// Applied step `index` with `params` and the steps after it, rendered in memory (card 0158):
  /// what `reviseStep` would write, up to the first host tool; nothing recorded.
  package func previewChain(from index: Int, params: ParamSet, level: ChainLevel = .full)
    async throws -> ChainPreview
  {
    try await session.previewChain(from: index, params: params, level: level)
  }

  /// Refuses a revise of step `index` with `params` that moves the pixels (under its recorded or
  /// its new values) while a masked step before `end` would replay on them: its recorded mask
  /// would land on other pixels (card 0160).
  private func refuseMovedMask(_ index: Int, params: ParamSet, until end: Int) throws {
    // The chain preview refuses by the same rule (card 0158).
    if let masked = session.movedMaskStep(index, params: params, until: end) {
      throw PipelineError.maskMoved(step: masked)
    }
  }

  /// The recorded masks of the steps a revise left pending from `start` (card 0159), read from
  /// disk for ▶ Run (`pendingMaskSteps` says which).
  package func pendingMasks(from start: Int, planned: [String]) throws -> [Int: AstroImage] {
    guard let version = session.history.versions.last else { return [:] }
    var masks: [Int: AstroImage] = [:]
    for index in try pendingMaskSteps(from: start, planned: planned) {
      masks[index] = try session.history.mask(ofVersion: version.id, step: index - version.base)
    }
    return masks
  }

  /// The steps a revise left pending from `start` that ▶ Run applies under a recorded mask,
  /// without reading one.
  ///
  /// Their masks are those of the chain the revise replaced (its last version), as long as the
  /// head is that revise's — the same steps, on the same parent, up to `start` — and only where
  /// the column plans the same process (`planned`, by index) at the same place; the version's
  /// undone steps carry none. A revised step that moves the pixels makes them land elsewhere:
  /// refused (`PipelineError.maskMoved`), as the revise refuses it (0160).
  package func pendingMaskSteps(from start: Int, planned: [String]) throws -> [Int] {
    let history = session.history
    guard let version = history.versions.last, version.base < start,
      history.steps.count == start, start - version.base <= version.steps.count,
      version.parent == (version.base == 0 ? nil : history.steps[version.base - 1].file),
      zip(history.steps[version.base..<start], version.steps)
        .allSatisfy({ $0.processID == $1.processID })
    else { return [] }
    let revised = history.steps[version.base]
    let moved =
      session.registry.movesPixels(revised.processID, params: revised.params)
      || session.registry.movesPixels(version.steps[0].processID, params: version.steps[0].params)
    let applied = version.steps.count - version.redo
    let masked = ((start - version.base)..<max(start - version.base, applied)).filter { offset in
      version.steps[offset].mask != nil && planned.indices.contains(version.base + offset)
        && planned[version.base + offset] == version.steps[offset].processID
    }
    if moved, let first = masked.first { throw PipelineError.maskMoved(step: version.base + first) }
    return masked.map { version.base + $0 }
  }

  /// Forgets history version `id` and removes the files only it kept (card 0159): no undo.
  package func dropVersion(_ id: String) throws {
    defer { mirror() }
    try session.history.dropVersion(id)
    cleanUp()
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
    // Matched in either language: the label was recorded in the language of its day.
    let wasBefore = ["en", "fr"].contains {
      version.label == Self.versionLabels(base: version.base, locale: Locale(identifier: $0)).before
    }
    let labels = Self.versionLabels(base: version.base)
    let replaced = try history.restore(
      version: id, replacedLabel: wasBefore ? labels.revised : labels.before)
    cleanUp()
    return replaced
  }

  /// The labels of the two chains of a revise of step `base`, as the Versions menu reads them
  /// (in the language of the day: a label is a recorded name, like a snapshot's).
  static func versionLabels(base: Int, locale: Locale? = nil) -> (before: String, revised: String) {
    var before: LocalizedStringResource = .app("Before revising step \(base + 1)")
    var revised: LocalizedStringResource = .app("Revised step \(base + 1)")
    if let locale {
      before.locale = locale
      revised.locale = locale
    }
    return (String(localized: before), String(localized: revised))
  }

  /// Whether `processID` with `params` runs a host tool (a step the registry cannot render, such
  /// as StarNet's, counts as one): the one rule of the revise, its refusal and `replayMain`.
  package func runsTool(_ processID: String, _ params: ParamSet) -> Bool {
    session.registry.type(id: processID)?.runsTool(params) ?? true
  }
}
