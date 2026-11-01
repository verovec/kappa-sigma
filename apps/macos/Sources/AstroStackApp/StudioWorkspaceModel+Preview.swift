package import Foundation
internal import ImageKit
internal import ProcessKit

extension StudioWorkspaceModel {
  /// Renders the panel's values now (the debounced preview calls it one frame after a change).
  package func previewNow() async {
    drawPreview()
  }

  /// Draws the panel's values on the head now; a failure shows the head, never an older preview.
  func drawPreview() {
    guard let panel else { return }
    do {
      let (preview, isChain) = try previewImage(panel)
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
    } catch {
      shown = nil
      chainStoppedBefore = nil
      failure = UserFacingError(error).message
      previewFailed = true
      if isPreviewing {
        isPreviewing = false
        try? show(head, statistics: headStatistics)
      }
    }
  }

  /// The panel's values on the head; while a main step of the panel's process is edited (card
  /// 0158), that step with them and the steps after it, up to the first host tool (a recipe has
  /// no mask) — and whether it is that chain.
  private func previewImage(_ panel: ProcessPanelModel) throws -> (AstroImage, isChain: Bool) {
    guard let editing = editedStep else {
      chainStoppedBefore = nil
      let image = try studio.preview(
        panel.type.id, params: panel.params, on: selection, mask: maskImage())
      return (image, false)
    }
    let chain = try studio.previewChain(from: editing, params: panel.params)
    chainStoppedBefore = chain.stoppedBefore
    return (chain.image, true)
  }

  /// The main step the open panel edits (card 0158): `editing` when the panel is that step's
  /// process — another process's panel never reads its values onto the edited step's schema,
  /// and previews and applies on the head as usual.
  var editedStep: Int? {
    guard let editing, let panel, selection == .main else { return nil }
    let steps = studio.session.history.steps
    guard steps.indices.contains(editing), steps[editing].processID == panel.type.id else {
      return nil
    }
    return editing
  }

  /// The banner of a chain preview stopped before a host tool, in `locale`, or `nil`.
  package func chainStopNotice(locale: Locale? = nil) -> LocalizedStringResource? {
    guard let index = chainStoppedBefore, studio.steps.indices.contains(index) else { return nil }
    let title = String(localized: stepTitle(of: studio.steps[index].processID, locale: locale))
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
    drawPreview()
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
    previewTask?.cancel()
    previewTask = Task { [weak self] in
      // One frame: a slider drag renders its last position, not every intermediate one.
      try? await Task.sleep(for: .milliseconds(16))
      guard !Task.isCancelled else { return }
      await self?.previewNow()
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
