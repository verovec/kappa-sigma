package import Foundation
internal import ProcessKit

// MARK: - Re-editing an applied step (card 0159)

extension StudioWorkspaceModel {
  /// Opens applied step `index` of the combined image with its recorded values.
  ///
  /// The preview draws its chain (card 0158) until the edit is cancelled or applied. Refused
  /// with its reason while a run, a replay or a tool moves a history, and on a layer's branch.
  package func editStep(_ index: Int) {
    if let reason = editRefusal(index) {
      failure = reason
      return
    }
    let step = studio.session.history.steps[index]
    // The step's own output is what the edit changes: no compare with it meanwhile.
    try? compare(toStep: nil)
    choose(step.processID, params: step.params)
    // After `choose`, which ends any other edit.
    editing = index
    failure = nil
  }

  /// Leaves the edit: the viewer shows the head, nothing moved.
  package func cancelEdit() {
    closePanel()
  }

  /// Why applied step `index` cannot be edited now, or `nil`.
  package func editRefusal(_ index: Int) -> LocalizedStringResource? {
    if let refusal = historyMoveRefusal { return refusal }
    let steps = studio.session.history.steps
    guard steps.indices.contains(index) else {
      return UserFacingError(HistoryError.noStep(index)).message
    }
    // A step the registry cannot render (StarNet's) has no panel to edit.
    guard registry.type(id: steps[index].processID) != nil else {
      return .app("This step has no panel to edit: undo back to it and apply it again.")
    }
    return nil
  }

  /// Why the combined image's steps cannot be edited, restored or dropped now, or `nil`: a run,
  /// a replay or a tool moving a history, or a layer's branch shown.
  package var historyMoveRefusal: LocalizedStringResource? {
    if isMovingHistory {
      return .app("A run, a replay or a tool is moving the image: wait for it, then edit.")
    }
    guard selection == .main else {
      return .app("Only the combined image's steps can be edited: show it first.")
    }
    return nil
  }
}

// MARK: - What the edit panel says (card 0159)

extension StudioWorkspaceModel {
  /// The header of the edit panel, « Step 3 · Stretch — editing », in `locale`; `nil` without
  /// an edit.
  package func editTitle(locale: Locale? = nil) -> LocalizedStringResource? {
    guard let index = editedStep else { return nil }
    let steps = studio.session.history.steps
    let title = String(localized: stepTitle(of: steps[index].processID, locale: locale))
    return .app("Step \(index + 1) · \(title) — editing", locale: locale)
  }

  /// How many steps after the edited one a revise replays: up to the first host tool
  /// (`StudioSession.toolStep`, the revise's own rule).
  package var editReplayed: Int? {
    guard let index = editedStep else { return nil }
    return (editStop ?? studio.session.history.steps.count) - index - 1
  }

  /// The host-tool step after the edited one a revise stops before, or `nil`.
  package var editStop: Int? {
    guard let index = editedStep, let panel else { return nil }
    return studio.session.toolStep(from: index + 1, revising: index, params: panel.params)
  }

  /// What Apply does after the edited step, in `locale`: the steps it replays, and the host
  /// tool it stops before (▶ Run applies it and the rest).
  package func editSummary(locale: Locale? = nil) -> [LocalizedStringResource] {
    guard let index = editedStep else { return [] }
    let stop = editStop
    let replayed = (stop ?? studio.session.history.steps.count) - index - 1
    var lines: [LocalizedStringResource] = [.app("Replays \(replayed) later steps", locale: locale)]
    if let stop {
      let steps = studio.session.history.steps
      let title = String(localized: stepTitle(of: steps[stop].processID, locale: locale))
      lines.append(
        .app(
          "Stops before \(title) (step \(stop + 1)): ▶ Run applies it and the rest",
          locale: locale))
    }
    return lines
  }

  /// The edited step was applied under a mask the history recorded (card 0160): the preview and
  /// the revise use that mask, not the mask row's.
  package var editUsesRecordedMask: Bool {
    guard let index = editedStep else { return false }
    return studio.session.history.steps[index].mask != nil
  }

  /// Why Apply change is greyed, or `nil`: the revise's own refusal (a host-tool step), or a
  /// choice still to make (greyed with the reason, never refused after the press).
  package func applyEditRefusal(locale: Locale? = nil) -> LocalizedStringResource? {
    guard let index = editedStep, let panel else { return nil }
    return StudioUndo.reviseRefusal(self, step: index, params: panel.params)
      ?? unchosenRefusal(panel, locale: locale)
  }

  /// Whether applied step `index` is recomputed by the edit open now (shown « to recompute »).
  package func isRecomputed(_ index: Int) -> Bool {
    guard let edited = editedStep else { return false }
    return index > edited
  }
}
