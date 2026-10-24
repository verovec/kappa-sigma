internal import ImageKit
internal import ProcessKit

extension StudioWorkspaceModel {
  /// Applies the panel's values at full resolution: the head moves (a failure is shown).
  package func apply() throws {
    guard let panel else { return }
    // Apply records what the viewer shows (R2): values not drawn yet (a value just typed, a
    // drag within the frame) are drawn first, and what was drawn is what is recorded.
    previewTask?.cancel()
    // On a new head the values are shown first: this Apply previews, the next one records.
    if isPreviewSuspended {
      resumePreview()
      return
    }
    if !isShowing(panel) { drawPreview() }
    guard isShowing(panel) else { return }
    // The values applied: a geometry panel is back at the identity once the pixels moved.
    let (id, params) = (panel.type.id, panel.params)
    var used: AstroImage?
    let before = head
    try reported {
      used = try maskImage()
      try studio.apply(id, params: params, on: selection, mask: used)
    }
    // A branch step is not a pipeline step (0122 carries them).
    guard selection == .main else {
      // The branch's head is the one written: the same bits say the values changed nothing.
      appliedNothing =
        before.width == head.width && StudioSession.samePixels(before.planes, head.planes)
      return
    }
    // The user's manual work becomes the recipe (R5): the pipeline records the step.
    pipeline?.applied(id, params: params, masked: used != nil)
    appliedNothing = studio.session.lastApplyChangedNothing
  }

  /// Back one step on the history shown.
  package func undo() throws {
    try reported { try studio.undo(on: selection) }
  }

  /// Forward one undone step on the history shown.
  package func redo() throws {
    try reported { try studio.redo(on: selection) }
  }

  /// Runs a history move, then shows the head; a failure is shown in the panel and rethrown.
  func reported(_ move: () throws -> Void) throws {
    do {
      try move()
      failure = nil
      previewFailed = false
    } catch {
      failure = UserFacingError(error).message
      previewFailed = false
      try? headChanged()
      throw error
    }
    do {
      try headChanged()
    } catch {
      // The history moved but its head could not be shown: say so, never a silent stale view.
      failure = UserFacingError(error).message
      throw error
    }
  }

  /// The history moved (an Apply, an undo, a pipeline run): the viewer, the panel's inputs and
  /// the catalogue follow the new head.
  func headChanged() throws {
    // Even when showing the head fails, no preview scheduled meanwhile outlives the move.
    let moved = headSteps != steps
    // The superseded head is never kept alive by its sample.
    headSample = nil
    defer { suspendPreview(moved: moved) }
    if dropRegionIfMoved() { resetMovingValues() }
    shown = nil
    // A report speaks of the head it was made on.
    toolReport = nil
    appliedNothing = false
    batch.showsModel = false
    defer { headStatistics = viewer.model.statistics }
    isPreviewing = false
    // A compared step undone, or off the head's grid (a crop applied), stops the compare.
    if let comparing,
      !onHeadGrid(step: comparing) || viewer.reference?.width != head.width
        || viewer.reference?.height != head.height
    {
      try compare(toStep: nil)
    }
    if let other = comparingWith, !comparable.contains(other) { try compare(with: nil) }
    try show(head)
    // After the viewer shows the new head: the display stretch offered is the one on screen.
    if let panel { refresh(panel) }
    refreshCatalogue()
  }
}
