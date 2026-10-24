package import Foundation

/// The app's own Siril settings file (cards 0093, 0094), passed with `-i`: Siril never reads or
/// rewrites the user's (a plain `platesolve` saves focal and pixel size as defaults, SPCC keeps
/// the last sensor and filter), and the local Gaia catalogues are the astro library's, so a
/// missing catalogue fails instead of Siril silently going online. `lang=en_US`: Siril's own
/// language setting outranks the environment's (card 0124), and its log is read in English.
package enum SirilAppSettings {
  /// The Gaia DR3 astrometric file Siril reads for `localgaia`.
  package static let astrometricFile = "siril_cat_healpix8_astro.dat"

  /// Writes the settings to `file` (rewritten before each run: Siril saves its whole
  /// configuration back into it on exit).
  package static func write(to file: URL, catalogues: URL) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let text = """
      [core]
      lang=en_US
      catalogue_gaia_astro=\(catalogues.appendingPathComponent(astrometricFile).path)
      catalogue_gaia_photo=\(catalogues.path)
      [astrometry]
      update_default_scale=false

      """
    try Data(text.utf8).write(to: file, options: .atomic)
  }
}
