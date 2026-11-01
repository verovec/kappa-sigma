package import Foundation
package import ProcessKit

// MARK: - Revising an applied step (card 0157)

extension StudioUndo {
  /// Revises applied step `index` of the combined image with `params`
  /// (`StudioModel.reviseStep`) and registers it as one move: ⌘Z puts the chain it replaced
  /// back (a history version, nothing recomputed), ⇧⌘Z the revised one.
  ///
  /// Refused, its reason in the panel, while a run, a replay or a tool moves a history, on a
  /// layer's branch (the main history only, E25), past the applied steps, and for a host-tool
  /// step itself (its panel comes with the re-edit UI). A failure half-way keeps the steps it
  /// applied, undoable too.
  package static func reviseStep(
    _ model: StudioWorkspaceModel, step index: Int, params: ParamSet,
    on undoManager: UndoManager?
  ) async {
    if let reason = reviseRefusal(model, step: index, params: params) {
      model.failure = reason
      return
    }
    let studio = model.studio
    model.isReplaying = true
    defer { model.isReplaying = false }
    let before = studio.session.history.versions.map(\.id)
    let files = studio.steps.map(\.file)
    // The column as it was: ⌘Z puts step `index`'s recipe back with the chain.
    let mark = model.pipeline?.mark(keeping: [index])
    do {
      try await studio.reviseStep(index, params: params)
      model.failure = nil
    } catch {
      model.failure = UserFacingError(error).message
    }
    // Never a silent stale view: a head that cannot be shown says so; a revise refused before
    // anything moved leaves the view as it is.
    if studio.steps.map(\.file) != files {
      do {
        try model.headChanged()
      } catch {
        model.failure = model.failure ?? UserFacingError(error).message
      }
    }
    // Read from the history, not returned by `reviseStep`: a revise that throws half-way keeps
    // its version and its steps, undoable too.
    guard let version = studio.session.history.versions.last, !before.contains(version.id)
    else { return }
    // The column's recipe goes back with the chain only if the revise changed it.
    let touched = model.pipeline?.revised(index, params: params) ?? false
    recordNew(
      model, steps: 0, in: .main, name: .app("Revise Step"), mark: touched ? mark : nil,
      version: version.id, on: undoManager)
  }

  /// Applies the edit open in `model` (card 0159), then closes the panel on the new head.
  ///
  /// The edited step is revised with the panel's values (`reviseStep`, one ⌘Z). A refused or
  /// failed revise keeps the edit open with its reason.
  package static func applyEdit(_ model: StudioWorkspaceModel, on undoManager: UndoManager?) async {
    guard let index = model.editedStep, let panel = model.panel else { return }
    // On a new head the values are shown first, as Apply does (R2: never revised unseen).
    if model.isPreviewSuspended {
      model.resumePreview()
      return
    }
    await reviseStep(model, step: index, params: panel.params, on: undoManager)
    // Refused before anything moved: the edit stays open with its reason. Once the head moved
    // (done, or failed half-way — the failure stays shown) the edit is over: never left as a
    // plain panel whose Apply would add the step on top.
    if model.failure != nil, model.editedStep == index { return }
    model.closePanel()
  }

  /// Why step `index` of `model` cannot be revised with `params` now, or `nil`.
  package static func reviseRefusal(
    _ model: StudioWorkspaceModel, step index: Int, params: ParamSet
  )
    -> LocalizedStringResource?
  {
    if model.isMovingHistory {
      return .app("A run, a replay or a tool is moving the image: wait for it, then revise.")
    }
    guard model.selection == .main else {
      return .app("Only the combined image's steps can be revised: show it first.")
    }
    let steps = model.studio.steps
    guard steps.indices.contains(index) else {
      return UserFacingError(HistoryError.noStep(index)).message
    }
    if model.studio.runsTool(steps[index].processID, params) {
      return .app("A host-tool step cannot be revised yet: undo back to it and apply it again.")
    }
    return nil
  }
}
