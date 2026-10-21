/// Why a background extraction was refused or produced nothing (tool failures are the tools'
/// own errors: `GraXpertError`, `SirilError`).
package enum BackgroundExtractionError: Error, Equatable, Sendable {
  /// `parameter` is `value`, outside the tool's `lower…upper`.
  case outOfRange(parameter: String, value: Double, lower: Double, upper: Double)
  /// The engine cannot apply `correction` (Siril's `subsky` only subtracts).
  case unsupportedCorrection(engine: BackgroundEngine, correction: BackgroundCorrection)
  /// The tool ended cleanly but the corrected image is not at `path`.
  case noOutput(path: String)
}
