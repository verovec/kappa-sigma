internal import Foundation

/// What a plate solve is told (card 0093): every value given by the user, none read from the
/// image behind their back (R2).
package struct PlateSolveRequest: Equatable, Sendable {
  /// Where the stars are looked up.
  package enum Catalogue: String, CaseIterable, Sendable {
    /// The Gaia DR3 extract under the catalogue folder (`just download-catalogues`): offline.
    case localGaia = "local-gaia"
    /// Gaia DR3 fetched from the network by Siril.
    case online = "online-gaia"

    /// Siril's `-catalog=` value.
    var sirilName: String {
      switch self {
      case .localGaia: "localgaia"
      case .online: "gaia"
      }
    }
  }

  /// The approximate centre: right ascension in degrees.
  package var raDegrees: Double
  /// The approximate centre: declination in degrees.
  package var decDegrees: Double
  /// Focal length, millimetres.
  package var focalMm: Double
  /// Pixel size, micrometres.
  package var pixelSizeUm: Double
  /// Faintest catalogue star used; `nil`: Siril's value for the field.
  package var limitMag: Double?
  /// Local or online stars.
  package var catalogue: Catalogue

  /// A request of these values.
  package init(
    raDegrees: Double, decDegrees: Double, focalMm: Double, pixelSizeUm: Double,
    limitMag: Double?, catalogue: Catalogue
  ) {
    self.raDegrees = raDegrees
    self.decDegrees = decDegrees
    self.focalMm = focalMm
    self.pixelSizeUm = pixelSizeUm
    self.limitMag = limitMag
    self.catalogue = catalogue
  }

  /// The arguments of `platesolve`.
  ///
  /// Always `-force` (a stack may carry a stale solution) and `-noflip` (the pixels stay as they
  /// are; only the solution is added).
  package var arguments: [String] {
    var arguments = [
      String(format: "%.6f,%.6f", raDegrees, decDegrees), "-force",
      "-focal=" + GoFormat.shortest(focalMm), "-pixelsize=" + GoFormat.shortest(pixelSizeUm),
    ]
    if let limitMag { arguments.append("-limitmag=" + GoFormat.shortest(limitMag)) }
    return arguments + ["-catalog=" + catalogue.sirilName, "-noflip"]
  }
}
