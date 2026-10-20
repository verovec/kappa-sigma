/// Why the finishing oracle cannot be read.
package enum FinishOracleError: Error, Equatable {
  /// `Fixtures/finish/manifest.json` is not in TestSupport's resources.
  case manifestMissing
  /// A file that is not a readable image, or two images of different sizes.
  case unreadable(String)
}
