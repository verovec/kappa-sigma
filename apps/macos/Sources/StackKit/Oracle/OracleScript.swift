/// One Siril script the legacy engine ran, as captured: `scripts/NNNN_<siril -d dir>.ssf`.
package struct OracleScript: Equatable, Sendable {
  /// The 1-based emission number (`NNNN`).
  package let number: Int
  /// The file name.
  package let name: String
  /// The base name of the working directory Siril ran in (`light_L`, `04_aligned`, …).
  package let directory: String
  /// The script, with paths normalized to `<ROOT>`/`<CAPTURES>` and the run id to `<RUN>`.
  package let text: String

  /// Splits `NNNN_<dir>.ssf`; `nil` for any other name.
  package init?(name: String, text: String) {
    guard name.hasSuffix(".ssf") else { return nil }
    let stem = name.dropLast(4)
    guard let underscore = stem.firstIndex(of: "_"),
      let number = Int(stem[..<underscore]), number > 0
    else { return nil }
    self.number = number
    self.name = name
    self.directory = String(stem[stem.index(after: underscore)...])
    self.text = text
  }
}
