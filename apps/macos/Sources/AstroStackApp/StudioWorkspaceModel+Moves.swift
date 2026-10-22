internal import ImageKit
internal import ProcessKit
internal import RenderKit

extension StudioWorkspaceModel {
  /// Whether the output of step `index` has the head's size (compare reads it pixel for pixel).
  func fitsHead(step index: Int) -> Bool {
    // The header alone: decoding the step's pixels on every head change would be wasted.
    guard let size = try? studio.session.history.size(ofStep: index) else { return false }
    return size.width == studio.head.width && size.height == studio.head.height
  }

  /// Drops the viewer's region when a history move applied or took back a geometric step (card
  /// 0090): its pixels belong to another part of the image even at the same size (a flip, a
  /// half turn).
  func dropRegionIfMoved(since before: [History.Step]) {
    let after = studio.steps
    let common = zip(before, after).prefix { $0 == $1 }.count
    let changed = before.dropFirst(common) + after.dropFirst(common)
    let moved = changed.contains { step in
      registry.type(id: step.processID).map { $0 is any GeometricProcess.Type } ?? false
    }
    if moved { viewer.model.clearRegion() }
  }

  /// Before the preview of `processID` with `params` replaces the image: a compare stops first
  /// when it moves the pixels, so the step is never drawn against them, even if the draw fails.
  func willShow(_ processID: String, _ params: ParamSet) {
    if comparing != nil, movedGrid((processID, params)) != nil { try? compare(toStep: nil) }
  }

  /// Drops the region when the moved grid on screen changed, and publishes whether one is shown.
  ///
  /// A geometric preview other than the identity appeared, changed or went away: the region's
  /// pixels are no longer under it, even at the same size. The compare normally stops earlier,
  /// in `willShow`, before the moved image is drawn; this is the backstop for any other path.
  func gridMoved(from old: (processID: String, params: ParamSet)?) {
    let now = movedGrid(shown.map { ($0.processID, $0.params) })
    if movedGrid(old) != now { viewer.model.clearRegion() }
    if now != nil, comparing != nil { try? compare(toStep: nil) }
    if showsMovedGrid != (now != nil) { showsMovedGrid = now != nil }
  }

  /// The values of a preview that moves pixels, or `nil` for one that leaves them in place.
  func movedGrid(_ values: (processID: String, params: ParamSet)?) -> ParamSet? {
    guard let values, let type = registry.type(id: values.processID),
      type is any GeometricProcess.Type, !GeometryProcess.isIdentity(values.params)
    else { return nil }
    return values.params
  }
}
