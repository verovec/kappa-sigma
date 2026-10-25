package import ImageKit

/// Where an image that already carries a solution points (card 0130): the plate-solve panel says
/// so, read-only, and a new solve stays the user's choice.
package struct PlateSolveStatus: Equatable, Sendable {
  /// The centre pixel's right ascension, J2000, degrees.
  package let raDeg: Double
  /// The centre pixel's declination, J2000, degrees.
  package let decDeg: Double
  /// The scale, from the CD matrix's determinant, arcsec per pixel.
  package let arcsecPerPixel: Double

  /// The status of an image of `width` × `height` solved as `wcs`; nil without a solution.
  package init?(wcs: WCS?, width: Int, height: Int) {
    guard let wcs else { return nil }
    let centre = wcs.sky(x: Double(width - 1) / 2, y: Double(height - 1) / 2)
    let determinant = wcs.cd[0] * wcs.cd[3] - wcs.cd[1] * wcs.cd[2]
    raDeg = centre.ra
    decDeg = centre.dec
    arcsecPerPixel = abs(determinant).squareRoot() * 3600
  }
}
