/// A FITS error with the file it happened in, so the user knows which of 300 frames is broken.
package struct FITSFileError: Error, Equatable, Sendable {
  /// The file's path.
  package let path: String
  /// What is wrong with it.
  package let reason: FITSError

  /// An error for `path`.
  package init(path: String, reason: FITSError) {
    self.path = path
    self.reason = reason
  }
}
