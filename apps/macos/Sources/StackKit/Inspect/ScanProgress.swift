/// Where a capture scan is, for the Import sheet: observation only, never an input of the scan.
package enum ScanProgress: Equatable, Sendable {
  /// Indexing the calibration library (`LibraryIndex`), before any frame is read.
  case library
  /// FITS headers read so far, out of every FITS file the folders hold.
  case reading(done: Int, total: Int)
  /// Grouping, verdicts and warnings over everything read.
  case classifying

  /// How often the reading count is reported (and always on the last file).
  package static let readingStep = 32
}
