/// What the geometry panel shows besides its values (card 0090): the output's size and what
/// becomes of the plate solution.
package struct GeometryOutput: Equatable {
  /// The plate solution of the output.
  package enum PlateSolution: Equatable {
    /// The head has none.
    case none
    /// Kept, moved with the pixels.
    case moved
    /// Removed: a fine angle resamples the frame.
    case removed
  }

  /// Columns, full resolution.
  package let width: Int
  /// Rows, full resolution.
  package let height: Int
  /// What happens to the plate solution.
  package let wcs: PlateSolution

  /// An output of `width` × `height` whose plate solution is `wcs`.
  package init(width: Int, height: Int, wcs: PlateSolution) {
    self.width = width
    self.height = height
    self.wcs = wcs
  }
}
