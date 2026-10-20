/// Why a recorded oracle case cannot be trusted or read.
package enum OracleCaseError: Error, Equatable, Sendable {
  /// The folder has no `manifest.json`.
  case missingManifest(path: String)
  /// A file the manifest lists is absent.
  case missingFile(String)
  /// A file's sha256 differs from the manifest: it changed after recording (re-record it).
  case hashMismatch(file: String)
  /// A `*.sha256` line is not `<64 hex>  <path>`.
  case malformedHashLine(file: String, line: Int)
}
