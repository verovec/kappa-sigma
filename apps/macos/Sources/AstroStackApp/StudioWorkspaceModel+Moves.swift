internal import ImageKit
internal import ProcessKit
internal import RenderKit

extension StudioWorkspaceModel {
  /// Whether step `index` lies on the head's grid: no geometric step after it moved the pixels
  /// (decided from the recorded values, no image read).
  func onHeadGrid(step index: Int) -> Bool {
    steps.indices.contains(index)
      && !steps[(index + 1)...].contains { movesPixels($0) }
  }

  /// The registry's rule on the step's values, the one `History.Step.movesPixels` records.
  private func movesPixels(_ step: History.Step) -> Bool {
    registry.movesPixels(step.processID, params: step.params)
  }

  /// Drops the viewer's region when the head changed through a step that moved the pixels.
  ///
  /// Applied, undone, redone or run by the pipeline: the region's pixels belong to another part
  /// of the image even at the same size (a flip, a half turn). Returns whether the pixels moved.
  @discardableResult
  func dropRegionIfMoved() -> Bool {
    let after = steps
    let common = zip(headSteps, after).prefix { $0 == $1 }.count
    let changed = headSteps.dropFirst(common) + after.dropFirst(common)
    headSteps = after
    guard changed.contains(where: movesPixels) else { return false }
    viewer.model.clearRegion()
    return true
  }

  /// Puts an open geometry panel back at the identity after the pixels moved.
  ///
  /// An Apply, an undo or redo, a pipeline run: its crops, turns, flips and angle were relative to
  /// the image they moved and would move the new head again. Its interpolation and canvas stay.
  func resetMovingValues() {
    guard let panel, panel.type == GeometryProcess.self else { return }
    let identity = ParamSet(schema: GeometryProcess.schema)
    let moving = ["cropLeft", "cropTop", "cropRight", "cropBottom", "rotation", "flipH", "flipV"]
    for id in moving + ["angle"] {
      if let value = identity[id], panel.params[id] != value { panel.set(id, value) }
    }
  }

  /// Before the preview of `processID` with `params` replaces the image: a compare stops first
  /// when it moves the pixels, so the step is never drawn against them, even if the draw fails.
  func willShow(_ processID: String, _ params: ParamSet) {
    if comparing != nil, movedGrid((processID, params)) != nil { try? compare(toStep: nil) }
  }

  /// Drops the region when the moved grid on screen changed, and publishes whether one is shown.
  ///
  /// A geometric preview other than the identity appeared, changed or went away: the region's
  /// pixels are no longer under it, even at the same size. The compare stops earlier, in
  /// `willShow`, the one place a moved image is drawn from.
  func gridMoved(from old: (processID: String, params: ParamSet)?) {
    let now = movedGrid(shown.map { ($0.processID, $0.params) })
    if movedGrid(old) != now { viewer.model.clearRegion() }
    if showsMovedGrid != (now != nil) { showsMovedGrid = now != nil }
  }

  /// The values of a preview that moves pixels, or `nil` for one that leaves them in place.
  func movedGrid(_ values: (processID: String, params: ParamSet)?) -> ParamSet? {
    guard let values,
      let type = registry.type(id: values.processID) as? any GeometricProcess.Type,
      !type.isIdentity(values.params)
    else { return nil }
    return values.params
  }
}
