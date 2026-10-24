/// A move of the image as shown, which a shortcut composes onto the geometry values (card 0105).
package enum GeometryMove: Sendable, CaseIterable {
  /// A quarter turn clockwise.
  case rotateClockwise
  /// A quarter turn counter-clockwise.
  case rotateCounterclockwise
  /// Left and right swapped.
  case flipHorizontally
  /// Top and bottom swapped.
  case flipVertically

  /// Whether it mirrors the image (a fine angle then turns the other way).
  var mirrors: Bool { self == .flipHorizontally || self == .flipVertically }
}
