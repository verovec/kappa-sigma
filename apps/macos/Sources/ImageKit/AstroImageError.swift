/// Why two images could not be combined.
package enum AstroImageError: Error, Equatable, Sendable {
  /// The other image is not `width` × `height` × `planes` like this one.
  case shapeMismatch(width: Int, height: Int, planes: Int)
}
