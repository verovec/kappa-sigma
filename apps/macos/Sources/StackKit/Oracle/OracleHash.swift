/// One line of `masters.sha256` / `bundle_layers.sha256`: the sha256 of a FITS data unit (the
/// header is excluded because Siril stamps a creation date in it) and the normalized path.
package struct OracleHash: Equatable, Sendable {
  /// Lower-case hex sha256 of the data unit.
  package let sha256: String
  /// The file's path with `<ROOT>`, `<CAPTURES>` and `<RUN>` placeholders.
  package let path: String

  /// Parses `<64 hex>  <path>` lines; blank lines are skipped.
  package static func parse(_ text: String, file: String) throws -> [Self] {
    try text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
      .compactMap { offset, line in
        guard !line.isEmpty else { return nil }
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[1].isEmpty, parts[0].count == 64,
          parts[0].allSatisfy({ $0.isHexDigit && !$0.isUppercase }), !parts[2].isEmpty
        else { throw OracleCaseError.malformedHashLine(file: file, line: offset + 1) }
        return Self(sha256: String(parts[0]), path: String(parts[2]))
      }
  }
}
