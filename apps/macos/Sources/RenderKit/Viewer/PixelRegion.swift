/// A rectangle of image pixels (array coordinates, rows in file order): the viewer's region for
/// exact previews and the histogram's sampling window.
package struct PixelRegion: Equatable, Sendable {
  /// Left column.
  package var x: Int
  /// Top row.
  package var y: Int
  /// Columns.
  package var width: Int
  /// Rows.
  package var height: Int

  /// The pixels from (`x`, `y`), `width` × `height`.
  package init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}
