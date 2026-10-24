/// What a header card is to a plate solution (card 0106): the one list every reader goes
/// through (`isWCS`, `droppingWCS()`, `moved(by:)`).
package enum SolutionKeyword: Equatable, Sendable {
  /// A card of the image's own solution (`CTYPE1`, `CD1_1`, `A_2_0`, `PLTSOLVD`…).
  case primary
  /// A card of an alternate solution (`CTYPE1A`, `WCSNAMEB`; FITS WCS paper I §3.5).
  case alternate
}

extension FITSHeader {
  /// What `keyword` is to a plate solution, or `nil` when it is none of it.
  ///
  /// Primary: the axis cards of any axis (`CTYPEn`…`CSYERn`, `CDi_j`, `PCi_j`, `PVi_j`, `PSi_j`),
  /// the frame and names (`RADESYS`, `EQUINOX`, `WCSAXES`…), the solver's flag (`PLTSOLVD`) and
  /// the SIP terms. Alternate: one of those followed by a letter A–Z (SIP has none).
  package static func solutionKeyword(_ keyword: String) -> SolutionKeyword? {
    if isPrimaryKeyword(keyword) { return .primary }
    guard let last = keyword.last, ("A"..."Z").contains(last) else { return nil }
    let base = String(keyword.dropLast())
    return alternateNamed.contains(base) || isAxisKeyword(base) ? .alternate : nil
  }

  private static let namedWCS: Set<String> = [
    "WCSAXES", "WCSNAME", "LONPOLE", "LATPOLE", "RADESYS", "RADECSYS", "EQUINOX", "PLTSOLVD",
    "A_ORDER", "B_ORDER", "AP_ORDER", "BP_ORDER",
  ]
  private static let axisPrefixes = [
    "CTYPE", "CUNIT", "CRPIX", "CRVAL", "CDELT", "CROTA", "CNAME", "CRDER", "CSYER",
  ]
  private static let matrixPrefixes = ["CD", "PC", "PV", "PS"]
  /// The named cards a solution letter may follow (`WCSAXESA`, `RADESYSB`…).
  private static let alternateNamed: Set<String> = [
    "WCSAXES", "WCSNAME", "LONPOLE", "LATPOLE", "RADESYS", "EQUINOX",
  ]

  private static func isPrimaryKeyword(_ keyword: String) -> Bool {
    namedWCS.contains(keyword) || isAxisKeyword(keyword) || isSIPTerm(keyword)
  }

  /// `CTYPEn`…`CSYERn` and `CDi_j`, `PCi_j`, `PVi_j`, `PSi_j` of any axes.
  private static func isAxisKeyword(_ keyword: String) -> Bool {
    if let prefix = axisPrefixes.first(where: keyword.hasPrefix) {
      return Int(keyword.dropFirst(prefix.count)) != nil
    }
    guard matrixPrefixes.contains(where: keyword.hasPrefix) else { return false }
    let indices = keyword.dropFirst(2).split(separator: "_", omittingEmptySubsequences: false)
    return indices.count == 2 && indices.allSatisfy { Int($0) != nil }
  }

  /// `A_p_q`, `B_p_q`, `AP_p_q`, `BP_p_q` (not the `_ORDER` cards).
  static func isSIPTerm(_ keyword: String) -> Bool {
    let parts = keyword.split(separator: "_", omittingEmptySubsequences: false)
    return parts.count == 3 && ["A", "B", "AP", "BP"].contains(String(parts[0]))
      && Int(parts[1]) != nil && Int(parts[2]) != nil
  }
}
