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
      let preview = try studio.preview(
        panel.type.id, params: panel.params, on: selection, mask: maskImage())
      // Through the head's display stretch: an auto-stretch fitted to the preview would hide
      // the very change the process makes (what is shown is what Apply records, R2).
      let same = preview.planes.count == headStatistics.count
      willShow(panel.type.id, panel.params)
      try show(preview, statistics: same ? headStatistics : nil)
      isPreviewing = true
      shown = (panel.type.id, panel.params, mask)
      // A preview clears only a preview's failure: an Apply or Undo failure stays in view.
      if previewFailed { failure = nil }
      previewFailed = false
    } catch {
      shown = nil
      failure = UserFacingError(error).message
      previewFailed = true
      if isPreviewing {
        isPreviewing = false
        try? show(head, statistics: headStatistics)
      }
    }
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
    if let panel { panel.suggestions = offers(for: panel.type, params: panel.params) }
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
