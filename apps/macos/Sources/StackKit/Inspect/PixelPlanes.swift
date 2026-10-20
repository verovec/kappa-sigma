/// A frame's pixels as planes of physical values in file row order (`planes[c][y * width + x]`).
package struct PixelPlanes: Equatable, Sendable {
  package var width: Int
  package var height: Int
  package var planes: [[Float]]

  /// The given planes.
  package init(width: Int, height: Int, planes: [[Float]]) {
    self.width = width
    self.height = height
    self.planes = planes
  }
}
