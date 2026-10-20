import Foundation
import ImageKit
import Testing

/// `cdDeterminant` is the legacy `Header.CDDeterminant` (`internal/fits/wcs.go`): its sign is the
/// parity the channel-master normalization compares.
@Suite("FITSHeader — WCS parity")
struct WCSParityTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let cards: [(String, String)]
    let want: Double?
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(name: "explicit CD matrix", cards: [("CD1_1", "-2"), ("CD1_2", "1"), ("CD2_1", "3"), ("CD2_2", "4")], want: -11),
    Case(name: "CDELT with identity PC", cards: [("CDELT1", "-0.5"), ("CDELT2", "0.5")], want: -0.25),
    Case(
      name: "CDELT with a rotation PC",
      cards: [("CDELT1", "2"), ("CDELT2", "3"), ("PC1_1", "0"), ("PC1_2", "1"), ("PC2_1", "1"), ("PC2_2", "0")],
      want: -6),
    Case(name: "an incomplete CD falls back to CDELT", cards: [("CD1_1", "5"), ("CDELT1", "1"), ("CDELT2", "1")], want: 1),
    Case(name: "no WCS", cards: [("OBJECT", "'M31'")], want: nil),
    Case(name: "a degenerate WCS", cards: [("CD1_1", "1"), ("CD1_2", "1"), ("CD2_1", "1"), ("CD2_2", "1")], want: nil),
  ]

  @Test("det(CD) from CD or CDELT × PC; nil without a usable WCS", arguments: cases)
  func testCDDeterminant(_ example: Case) throws {
    let data = FITSBytes.float32(
      width: 1, height: 1, planes: [[0]], extra: example.cards.map { FITSBytes.card($0.0, $0.1) })
    let header = try FITSFile.parse(data).header
    #expect(header.cdDeterminant == example.want)
  }
}
