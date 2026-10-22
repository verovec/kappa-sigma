/// Why « Use region » cannot fill the crop now.
package enum RegionUnavailable: Equatable {
  /// The panel is not geometry's.
  case notGeometry
  /// No region is drawn in the viewer.
  case noRegion
  /// The viewer shows a moved preview: a region drawn on it is not in the head's pixels.
  case previewMoved
}
