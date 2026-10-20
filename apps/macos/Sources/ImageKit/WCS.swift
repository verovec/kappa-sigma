internal import Foundation

/// A gnomonic (TAN) plate solution from the header: array pixel → RA/Dec, in degrees.
///
/// Reads `CRPIX`/`CRVAL` with either the `CD` matrix, `PC` × `CDELT`, or `CDELT` + `CROTA2`
/// (FITS WCS paper II, Calabretta & Greisen 2002, §5.1.3; the AIPS convention for `CROTA2`).
/// `RA---TAN` and `RA---TAN-SIP` (Shupe et al. 2005, what Siril's solver writes) are read; any
/// other projection, or a header without a scale, has no
/// solution (`nil`) rather than an approximate one.
package struct WCS: Equatable, Sendable {
  /// FITS reference pixel (1-based).
  package let crpix: SIMD2<Double>
  /// RA, Dec of the reference pixel, degrees.
  package let crval: SIMD2<Double>
  /// Degrees per pixel: `[CD1_1, CD1_2, CD2_1, CD2_2]`.
  package let cd: SIMD4<Double>
  /// SIP pixel-to-sky distortion (`A_p_q`, `B_p_q`); empty for plain TAN.
  package let sip: [SIPTerm]

  /// One SIP monomial u^`uPower` · v^`vPower`, times `onU` (A) added to u, times `onV` (B) to v.
  package struct SIPTerm: Equatable, Sendable {
    let uPower: Int
    let vPower: Int
    let onU: Double
    let onV: Double
  }

  /// The header's TAN solution, or `nil`.
  package init?(header: FITSHeader) {
    let projections = (header.string("CTYPE1") ?? "", header.string("CTYPE2") ?? "")
    let sip = projections.0.hasSuffix("-TAN-SIP") && projections.1.hasSuffix("-TAN-SIP")
    guard sip || (projections.0.hasSuffix("-TAN") && projections.1.hasSuffix("-TAN")),
      let crpix1 = header.double("CRPIX1"), let crpix2 = header.double("CRPIX2"),
      let crval1 = header.double("CRVAL1"), let crval2 = header.double("CRVAL2"),
      let cd = Self.matrix(header)
    else { return nil }
    crpix = SIMD2(crpix1, crpix2)
    crval = SIMD2(crval1, crval2)
    self.cd = cd
    self.sip = sip ? Self.sipTerms(header) : []
  }

  /// RA in [0, 360) and Dec of the array pixel (`x`, `y`) (0-based, file row order).
  package func sky(x: Double, y: Double) -> (ra: Double, dec: Double) {
    let offset = SIMD2(x + 1, y + 1) - crpix
    var (dx, dy) = (offset.x, offset.y)
    for term in sip {
      let monomial = pow(offset.x, Double(term.uPower)) * pow(offset.y, Double(term.vPower))
      dx += term.onU * monomial
      dy += term.onV * monomial
    }
    let xi = cd[0] * dx + cd[1] * dy
    let eta = cd[2] * dx + cd[3] * dy
    let radians = Double.pi / 180
    // Native spherical coordinates of the tangent-plane point; native pole at φp = 180°.
    let phi = atan2(xi, -eta)
    let theta = atan2(180 / Double.pi, (xi * xi + eta * eta).squareRoot())
    let dec0 = crval.y * radians
    let ra =
      crval.x * radians
      + atan2(
        -cos(theta) * sin(phi - .pi),
        sin(theta) * cos(dec0) - cos(theta) * sin(dec0) * cos(phi - .pi))
    let dec = asin(sin(theta) * sin(dec0) + cos(theta) * cos(dec0) * cos(phi - .pi))
    let degrees = (ra / radians).truncatingRemainder(dividingBy: 360)
    return (degrees < 0 ? degrees + 360 : degrees, dec / radians)
  }

  /// The `A_p_q`/`B_p_q` terms up to `A_ORDER`/`B_ORDER` (absent coefficients are 0).
  private static func sipTerms(_ header: FITSHeader) -> [SIPTerm] {
    let order = max(header.int("A_ORDER") ?? 0, header.int("B_ORDER") ?? 0)
    guard order >= 2 else { return [] }
    return (0...order).flatMap { uPower in
      (0...(order - uPower)).compactMap { vPower -> SIPTerm? in
        let onU = header.double("A_\(uPower)_\(vPower)") ?? 0
        let onV = header.double("B_\(uPower)_\(vPower)") ?? 0
        guard onU != 0 || onV != 0 else { return nil }
        return SIPTerm(uPower: uPower, vPower: vPower, onU: onU, onV: onV)
      }
    }
  }

  /// The CD matrix from `CDi_j` (missing cards 0), else `PCi_j` (missing cards: the identity)
  /// × `CDELTi`, else `CDELTi` + `CROTA2` — FITS WCS paper I §2.1.2: any `CDi_j` card selects CD.
  private static func matrix(_ header: FITSHeader) -> SIMD4<Double>? {
    let names = ["1_1", "1_2", "2_1", "2_2"]
    let cd = names.map { header.double("CD\($0)") }
    if cd.contains(where: { $0 != nil }) {
      return SIMD4(cd.map { $0 ?? 0 })
    }
    guard let cdelt1 = header.double("CDELT1"), let cdelt2 = header.double("CDELT2") else {
      return nil
    }
    let pc = names.map { header.double("PC\($0)") }
    if pc.contains(where: { $0 != nil }) {
      let identity: [Double] = [1, 0, 0, 1]
      let matrix = zip(pc, identity).map { $0 ?? $1 }
      return SIMD4(cdelt1, cdelt1, cdelt2, cdelt2) * SIMD4(matrix)
    }
    let rho = (header.double("CROTA2") ?? 0) * .pi / 180
    return SIMD4(cdelt1 * cos(rho), -cdelt2 * sin(rho), cdelt1 * sin(rho), cdelt2 * cos(rho))
  }
}
