package import Foundation
internal import ImageKit
internal import ProcessKit

extension StudioWorkspaceModel {
  /// Renders the panel's values now, in place of a render scheduled or in flight, and waits
  /// for it (a render the history moves under meanwhile is cancelled like any other).
  package func previewNow() async {
    startPreview()
    await previewTask?.value
  }

  /// Draws the panel's values on the head, or the chain from the step being edited.
  ///
  /// While a main step of the panel's process is edited (card 0158) the chain is that step with
  /// the panel's values and the steps after it, up to the first host tool, each under its
  /// recorded mask (0160). A failure shows the head, never an older preview. A chain lets the
  /// main actor go between its steps (card 0187): a render cancelled meanwhile — the next value,
  /// the panel closed — shows nothing, and is no failure.
  func drawPreview() async {
    // Cancelled before it started (the history moved, the panel closed): nothing is drawn — not
    // even the head's values, which a suspended panel must not show before Apply (R2).
    guard !Task.isCancelled, let panel else { return }
    guard let editing = editedStep else { return drawHeadPreview() }
    do {
      let chain = try await studio.previewChain(from: editing, params: panel.params)
      guard !Task.isCancelled, self.panel === panel else { return }
      chainStoppedBefore = chain.stoppedBefore
      try display(chain.image, of: panel, isChain: true)
    } catch is CancellationError {
      // Replaced or closed while it rendered: the viewer stays as it is.
    } catch {
      previewFailed(error)
    }
  }

  /// Draws the panel's values on the head now (one GPU step): what Apply shows before it
  /// records when nothing was drawn yet (R2).
  func drawHeadPreview() {
    guard let panel else { return }
    do {
      chainStoppedBefore = nil
      let image = try studio.preview(
        panel.type.id, params: panel.params, on: selection, mask: maskImage())
      try display(image, of: panel, isChain: false)
    } catch {
      previewFailed(error)
    }
  }

  /// Shows `preview` as the panel's values (`isChain`: the chain from the edited step).
  private func display(_ preview: AstroImage, of panel: ProcessPanelModel, isChain: Bool) throws {
    // Through the head's display stretch: an auto-stretch fitted to the preview would hide
    // the very change the process makes (what is shown is what Apply records, R2).
    let same = preview.planes.count == headStatistics.count
    willShow(panel.type.id, panel.params)
    try show(preview, statistics: same ? headStatistics : nil, subject: .preview)
    isPreviewing = true
    // A chain is not the panel's values on the head: Apply never records it as such.
    shown = isChain ? nil : (panel.type.id, panel.params, mask)
    // A preview clears only a preview's failure: an Apply or Undo failure stays in view.
    if previewFailed { failure = nil }
    previewFailed = false
  }

  /// The preview failed: the head is shown with the reason.
  private func previewFailed(_ error: any Error) {
    shown = nil
    chainStoppedBefore = nil
    failure = UserFacingError(error).message
    previewFailed = true
    if isPreviewing {
      isPreviewing = false
      try? show(head, statistics: headStatistics)
    }
  }

  /// The main step the open panel edits (card 0158): `editing` when the panel is that step's
  /// process — another process's panel never reads its values onto the edited step's schema,
  /// and previews and applies on the head as usual.
  package var editedStep: Int? {
    guard let editing, let panel, selection == .main else { return nil }
    let steps = studio.session.history.steps
    guard steps.indices.contains(editing), steps[editing].processID == panel.type.id else {
      return nil
    }
    return editing
  }

  /// The banner of a chain preview stopped before a host tool, in `locale`, or `nil`.
  package func chainStopNotice(locale: Locale? = nil) -> LocalizedStringResource? {
    // The steps `editedStep` and the chain read: the session's history.
    let steps = studio.session.history.steps
    guard let index = chainStoppedBefore, steps.indices.contains(index) else { return nil }
    let title = String(localized: stepTitle(of: steps[index].processID, locale: locale))
    return .app(
      "Preview stopped before \(title) (step \(index + 1)) — computed when applied", locale: locale)
  }

  /// Whether the viewer shows the current values and mask of `panel`.
  func isShowing(_ panel: ProcessPanelModel) -> Bool {
    guard let shown else { return false }
    return shown.processID == panel.type.id && shown.params == panel.params && shown.mask == mask
  }

  /// Shows the panel's values on the head again, after the history moved under it.
  package func resumePreview() {
    guard panel != nil else { return }
    isPreviewSuspended = false
    // The head's values show at once (Apply records what it showed, R2); a chain is a task's
    // work, drawn in place of any render scheduled or in flight.
    guard editedStep != nil else { return drawHeadPreview() }
    startPreview()
  }

  /// A value moved: the suggestions follow the values they depend on, the preview follows.
  func panelChanged() {
    // The notice spoke of the values applied, not of these.
    appliedNothing = false
    if let panel {
      panel.suggestions = offers(for: panel.type, params: panel.params)
    }
    greyUnavailable()
    // The head comes back now: a preview cancelled or refused would leave the model on screen.
    hideModel()
    schedulePreview()
  }

  func schedulePreview() {
    isPreviewSuspended = false
    // One frame: a slider drag renders its last position, not every intermediate one.
    startPreview(debounce: .milliseconds(16))
  }

  /// The one launcher of a render (card 0187): replaces the render scheduled or in flight,
  /// waits `debounce` when given, and draws unless cancelled meanwhile.
  func startPreview(debounce: Duration? = nil) {
    previewTask?.cancel()
    previewTask = Task { [weak self] in
      if let debounce { try? await Task.sleep(for: debounce) }
      guard !Task.isCancelled else { return }
      await self?.drawPreview()
    }
  }

  func stopPreview() {
    previewTask?.cancel()
    shown = nil
    chainStoppedBefore = nil
    guard isPreviewing else { return }
    isPreviewing = false
    try? show(head)
  }

  /// Suspends the panel's preview once the history moved under it.
  ///
  /// The viewer stays on the new head: previewing the values again would show an Apply twice and
  /// an Undo as nothing, so the panel says so and Apply reads Preview. A history that did not
  /// move (a refused move) previews again; a host tool has no preview.
  func suspendPreview(moved: Bool) {
    guard moved else {
      // Nothing changed: a suspended panel stays so, a previewing one previews again.
      if panel != nil, !isPreviewSuspended { schedulePreview() }
      return
    }
    // The step edited is gone or another one now: the edit ends with the move (before the
    // preview it schedules is cancelled).
    editing = nil
    chainStoppedBefore = nil
    previewTask?.cancel()
    previewTask = nil
    isPreviewSuspended = panel.map { !$0.type.runsTool($0.params) } ?? false
  }

  /// Waits for the preview scheduled by the last change, if any: a test sees a preview the
  /// debounce would draw later, without sleeping.
  package func settlePreview() async {
    await previewTask?.value
  }
}
