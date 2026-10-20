/// One applied process of an image's non-destructive history (0049).
package struct HistoryStep: Equatable, Sendable {
  /// The file a step wrote, counted by the disk budget.
  package struct Output: Equatable, Sendable {
    /// Path relative to the package.
    package let path: String
    /// Size in bytes.
    package let bytes: Int64

    /// An output file.
    package init(path: String, bytes: Int64) {
      self.path = path
      self.bytes = bytes
    }
  }

  /// Row id.
  package let id: Int64
  /// The image it belongs to.
  package let imageID: Int64
  /// 1-based position in the image's history.
  package let ordinal: Int
  /// The process that ran (`stretch.mtf`…).
  package let processID: String
  /// The parameters applied, as JSON (values applied = values shown, R2).
  package let paramsJSON: String
  /// The written file's path, if the step wrote one.
  package let outputPath: String?
  /// The written file's size in bytes (0 without a file).
  package let outputBytes: Int64
  /// sha256 of the output, when known.
  package let contentHash: String?
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64
}
