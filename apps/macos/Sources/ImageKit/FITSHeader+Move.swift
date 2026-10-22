extension FITSHeader {
  /// The header of the image `map` makes of this header's image (card 0090).
  ///
  /// A TAN or TAN-SIP plate solution moves with the pixels (every star keeps its RA/Dec); any
  /// other solution, and any alternate one (`CTYPE1A`…), is removed rather than left wrong.
  /// Every other card stays.
  ///
  /// With `p' = M·p + t`: `CRPIX' = M·CRPIX + t`, `CD' = CD·M⁻¹`, and the SIP polynomials become
  /// `S'(u') = M·S(M⁻¹·u')` (the forward `A`/`B` and the inverse `AP`/`BP` alike).
  package func moved(by map: GridMap) -> FITSHeader {
    guard let wcs = WCS(header: self) else { return droppingWCS() }
    let inverse = map.inverse
    let crpix =
      SIMD2(
        Double(map.matrix[0]) * wcs.crpix.x + Double(map.matrix[1]) * wcs.crpix.y,
        Double(map.matrix[2]) * wcs.crpix.x + Double(map.matrix[3]) * wcs.crpix.y)
      + SIMD2(Double(map.offset.x), Double(map.offset.y))
    let cd = wcs.cd
    let (i0, i1, i2, i3) = (
      Double(inverse[0]), Double(inverse[1]), Double(inverse[2]), Double(inverse[3])
    )
    let moved: [(String, Double)] = [
      ("CRPIX1", crpix.x), ("CRPIX2", crpix.y),
      ("CD1_1", cd[0] * i0 + cd[1] * i2), ("CD1_2", cd[0] * i1 + cd[1] * i3),
      ("CD2_1", cd[2] * i0 + cd[3] * i2), ("CD2_2", cd[2] * i1 + cd[3] * i3),
    ]
    let polynomials = movedPolynomial("A", "B", map) + movedPolynomial("AP", "BP", map)
    let replaced = cards.filter {
      !Self.isMovedKeyword($0.keyword) && !Self.isAlternateWCSKeyword($0.keyword)
    }
    return FITSHeader(
      cards: replaced + (moved + polynomials).map { Card(keyword: $0.0, number: $0.1) })
  }

  /// This header without any plate-solution card (an image resampled at an angle needs a new
  /// solve: an approximate solution would read wrong coordinates).
  package func droppingWCS() -> FITSHeader {
    FITSHeader(cards: cards.filter { !Self.isWCSKeyword($0.keyword) })
  }

  /// The SIP coefficients of `u`/`v` (`A`/`B`, or `AP`/`BP`) after `map`.
  private func movedPolynomial(_ uName: String, _ vName: String, _ map: GridMap)
    -> [(String, Double)]
  {
    let order = max(int(uName + "_ORDER") ?? 0, int(vName + "_ORDER") ?? 0)
    guard order >= 1 else { return [] }
    let inverse = map.inverse
    // u = M⁻¹·u': each old coordinate is ± one new coordinate.
    let uFrom = inverse[0] != 0 ? (axis: 0, sign: inverse[0]) : (axis: 1, sign: inverse[1])
    let vFrom = inverse[2] != 0 ? (axis: 0, sign: inverse[2]) : (axis: 1, sign: inverse[3])
    var moved: [SIMD2<Int>: SIMD2<Double>] = [:]
    for uPower in 0...order {
      for vPower in 0...(order - uPower) {
        let onU = double("\(uName)_\(uPower)_\(vPower)") ?? 0
        let onV = double("\(vName)_\(uPower)_\(vPower)") ?? 0
        guard onU != 0 || onV != 0 else { continue }
        var powers = SIMD2(0, 0)
        powers[uFrom.axis] += uPower
        powers[vFrom.axis] += vPower
        let sign = Double(Self.power(uFrom.sign, uPower) * Self.power(vFrom.sign, vPower))
        let vector = SIMD2(
          Double(map.matrix[0]) * onU + Double(map.matrix[1]) * onV,
          Double(map.matrix[2]) * onU + Double(map.matrix[3]) * onV)
        moved[powers, default: .zero] += sign * vector
      }
    }
    return moved.keys.sorted { ($0.x, $0.y) < ($1.x, $1.y) }.flatMap { powers in
      let vector = moved[powers] ?? .zero
      return [
        ("\(uName)_\(powers.x)_\(powers.y)", vector.x),
        ("\(vName)_\(powers.x)_\(powers.y)", vector.y),
      ]
    }
  }

  private static func power(_ sign: Int, _ exponent: Int) -> Int {
    exponent.isMultiple(of: 2) ? 1 : sign
  }

  /// The cards `moved(by:)` rewrites: the reference pixel, the matrix and the SIP terms.
  private static func isMovedKeyword(_ keyword: String) -> Bool {
    ["CRPIX1", "CRPIX2", "CDELT1", "CDELT2", "CROTA1", "CROTA2"].contains(keyword)
      || isMatrixKeyword(keyword) || isSIPTerm(keyword)
  }

  private static let namedWCS: Set<String> = [
    "WCSAXES", "WCSNAME", "LONPOLE", "LATPOLE", "RADESYS", "RADECSYS", "EQUINOX", "PLTSOLVD",
    "A_ORDER", "B_ORDER", "AP_ORDER", "BP_ORDER",
  ]
  private static let axisPrefixes = [
    "CTYPE", "CUNIT", "CRPIX", "CRVAL", "CDELT", "CROTA", "CNAME", "CRDER", "CSYER",
  ]
  private static let matrixPrefixes = ["CD", "PC", "PV", "PS"]

  /// Every card of a plate solution, primary or alternate: the axis cards (`CTYPEn`, `CRPIXn`,
  /// `CDi_j`, `PVi_j`…), the frame (`RADESYS`, `EQUINOX`), the solver's flag (`PLTSOLVD`) and
  /// the SIP terms.
  private static func isWCSKeyword(_ keyword: String) -> Bool {
    namedWCS.contains(keyword) || isMovedKeyword(keyword) || isPrimaryAxisKeyword(keyword)
      || isAlternateWCSKeyword(keyword)
  }

  /// A card of an alternate solution: a primary WCS keyword followed by a letter A–Z
  /// (`CTYPE1A`, `CD1_1B`, `WCSNAMEA`; FITS WCS paper I §3.5).
  private static func isAlternateWCSKeyword(_ keyword: String) -> Bool {
    guard let last = keyword.last, last.isUppercase, last.isLetter, keyword.count > 2 else {
      return false
    }
    let base = String(keyword.dropLast())
    return base == "WCSNAME" || base == "LONPOLE" || base == "LATPOLE" || base == "RADESYS"
      || base == "EQUINOX" || isPrimaryAxisKeyword(base)
  }

  /// `CTYPEn`…`CSYERn` and `CDi_j`, `PCi_j`, `PVi_j`, `PSi_j` of any axes.
  private static func isPrimaryAxisKeyword(_ keyword: String) -> Bool {
    if let prefix = axisPrefixes.first(where: keyword.hasPrefix) {
      return Int(keyword.dropFirst(prefix.count)) != nil
    }
    guard matrixPrefixes.contains(where: keyword.hasPrefix) else { return false }
    let indices = keyword.dropFirst(2).split(separator: "_", omittingEmptySubsequences: false)
    return indices.count == 2 && indices.allSatisfy { Int($0) != nil }
  }

  private static func isMatrixKeyword(_ keyword: String) -> Bool {
    ["CD", "PC"].contains { prefix in
      ["1_1", "1_2", "2_1", "2_2"].contains { keyword == prefix + $0 }
    }
  }

  /// `A_p_q`, `B_p_q`, `AP_p_q`, `BP_p_q` (not the `_ORDER` cards).
  private static func isSIPTerm(_ keyword: String) -> Bool {
    let parts = keyword.split(separator: "_", omittingEmptySubsequences: false)
    return parts.count == 3 && ["A", "B", "AP", "BP"].contains(String(parts[0]))
      && Int(parts[1]) != nil && Int(parts[2]) != nil
  }
}
