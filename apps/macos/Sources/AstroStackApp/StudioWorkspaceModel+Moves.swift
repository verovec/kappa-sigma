internal import ImageKit
internal import ProcessKit
internal import RenderKit

extension StudioWorkspaceModel {
  /// Whether the output of step `index` has the head's size (compare reads it pixel for pixel).
  func fitsHead(step index: Int) -> Bool {
    guard let image = try? studio.session.history.output(ofStep: index) else { return false }
    return image.width == studio.head.width && image.height == studio.head.height
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
}
