internal import ImageKit
internal import ProcessKit
internal import RenderKit

extension StudioWorkspaceModel {
  /// Why « Use region » is disabled, or `nil` when it can fill the crop.
  package var regionUnavailable: RegionUnavailable? {
    guard panel?.type == GeometryProcess.self else { return .notGeometry }
    guard viewer.model.frame.region != nil else { return .noRegion }
    // A region drawn on a moved preview (a crop, but also a same-size flip or half turn) is
    // not in the head's pixels.
    guard let panel, !isPreviewing || GeometryProcess.isIdentity(panel.params) else {
      return .previewMoved
    }
    return nil
  }

  /// Fills the four crops from the viewer's region (display pixels of the head, the values the
  /// panel reads), then clears the region; the preview follows, nothing is applied (R2).
  package func useRegion() {
    guard regionUnavailable == nil, let panel, let region = viewer.model.frame.region else {
      return
    }
    let head = studio.head
    let crops: [(String, Int)] = [
      ("cropLeft", region.x), ("cropTop", region.y),
      ("cropRight", head.width - region.x - region.width),
      ("cropBottom", head.height - region.y - region.height),
    ]
    for (id, pixels) in crops { panel.set(id, .number(Double(pixels))) }
    viewer.model.clearRegion()
  }

  /// The geometry panel's output on the head, or `nil` (another panel, values leaving no pixel).
  package var geometryOutput: GeometryOutput? {
    guard let panel, panel.type == GeometryProcess.self else { return nil }
    let head = studio.head
    guard
      let size = try? GeometryProcess.outputSize(
        panel.params, width: head.width, height: head.height)
    else { return nil }
    let wcs: GeometryOutput.PlateSolution =
      head.metadata.wcs == nil
      ? .none : GeometryProcess.removesWCS(panel.params) ? .removed : .moved
    return GeometryOutput(width: size.width, height: size.height, wcs: wcs)
  }
}
