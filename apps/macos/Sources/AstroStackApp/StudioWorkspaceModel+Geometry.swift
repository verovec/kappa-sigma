internal import ImageKit
package import ProcessKit
internal import RenderKit

extension StudioWorkspaceModel {
  /// Why « Use region » is disabled, or `nil` when it can fill the crop.
  package var regionUnavailable: RegionUnavailable? {
    guard panel?.type == GeometryProcess.self else { return .notGeometry }
    guard viewer.model.frame.region != nil else { return .noRegion }
    // A region drawn on a moved preview (a crop, but also a same-size flip or half turn) is
    // not in the head's pixels.
    // The values on screen, not the panel's: those may not be drawn yet, or failed to draw.
    guard !showsMovedGrid else { return .previewMoved }
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

  /// Whether a rotate or flip shortcut may act: no host tool running from the panel (it must
  /// not be swapped out under the run), no pipeline running, and no panel, the geometry panel,
  /// or another one still at its defaults — a slipped key never throws away unapplied values.
  package var canMoveGeometry: Bool {
    // The task covers the instant before the run starts; the run is what SwiftUI observes.
    guard toolTask == nil, toolRun == nil, pipeline?.isRunning != true else { return false }
    guard let panel, panel.type != GeometryProcess.self else { return true }
    return panel.params == ParamSet(schema: panel.type.schema)
  }

  /// Edit › Rotate / Flip (card 0105): `move` of the image shown, onto the geometry panel.
  ///
  /// The panel opens at the identity when none or an untouched one is shown; the preview
  /// follows, only ⌘E applies (R2).
  package func moveGeometry(_ move: GeometryMove) {
    guard canMoveGeometry else { return }
    guard let panel, panel.type == GeometryProcess.self else {
      // Opened at the move itself: one preview, not the identity's first.
      let identity = ParamSet(schema: GeometryProcess.schema)
      choose(GeometryProcess.id, params: GeometryProcess.composing(move, onto: identity))
      return
    }
    panel.replace(GeometryProcess.composing(move, onto: panel.params))
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
