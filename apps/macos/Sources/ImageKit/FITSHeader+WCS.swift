internal import Foundation

extension FITSHeader {
  /// Whether `keyword` belongs to the image's own plate solution (`SolutionKeyword.primary`; an
  /// alternate solution is not read, and an image that moves nothing keeps it).
  package static func isWCS(_ keyword: String) -> Bool {
    solutionKeyword(keyword) == .primary
  }

  /// The cards of its plate solution, in order.
  package var wcsCards: [Card] {
    cards.filter { Self.isWCS($0.keyword) }
  }

  /// This header describing an image solved as `wcs`.
  ///
  /// Unchanged when it already says so, else its WCS cards replaced by those of `wcs`. For `nil`,
  /// a solution it carries is dropped; cards no solution can be read from are left as they are
  /// (nothing in them was the image's).
  package func carrying(_ wcs: WCS?) -> FITSHeader {
    let solution = wcs?.cards ?? []
    guard wcsCards != solution, wcs != nil || WCS(header: self) != nil else { return self }
    return FITSHeader(cards: cards.filter { !Self.isWCS($0.keyword) } + solution)
  }

  /// det(CD) of the solved WCS (`Header.CDDeterminant`): the explicit CD matrix when all four
  /// cards are present, else CDELT × PC (PC defaulting to identity, Siril's representation).
  ///
  /// The sign is the image's mirror parity; nil when there is no WCS or it is degenerate (zero).
  package var cdDeterminant: Double? {
    let determinant: Double
    if let c11 = double("CD1_1"), let c12 = double("CD1_2"), let c21 = double("CD2_1"),
      let c22 = double("CD2_2")
    {
      determinant = c11 * c22 - c12 * c21
    } else if let d1 = double("CDELT1"), let d2 = double("CDELT2") {
      let (p11, p12) = (double("PC1_1") ?? 1, double("PC1_2") ?? 0)
      let (p21, p22) = (double("PC2_1") ?? 0, double("PC2_2") ?? 1)
      determinant = d1 * d2 * (p11 * p22 - p12 * p21)
    } else {
      return nil
    }
    return determinant == 0 ? nil : determinant
  }
}
