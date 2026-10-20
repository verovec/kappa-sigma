/// `manifest.json`: how a case was recorded and the sha256 of every top-level recorded file.
package struct OracleManifest: Decodable, Sendable {
  /// The case folder name (`golden-single-night`, `m31-db`, …).
  package let caseName: String
  /// A one-line description of the case.
  package let title: String
  /// `siril-cli --version` of the recording host.
  package let siril: String
  /// The timezone night keys were computed in.
  package let timezone: String
  /// The `../stacking-astro` commit that recorded the case.
  package let legacyCommit: String
  /// For the single-night golden: whether the legacy repo's pinned golden matched.
  package let legacyGolden: String?
  /// File name → sha256 (hex) of each top-level file of the case.
  package let files: [String: String]

  private enum CodingKeys: String, CodingKey {
    case caseName = "case"
    case title, siril, timezone, legacyCommit, legacyGolden, files
  }
}
