import Foundation
import ImageKit
import StackKit
import Testing

/// The per-night parity rule (`fits.Header.CDDeterminant` + `parityCache`): the sign of det(CD)
/// read from a no-flip plate solve, Siril 1.4.3's PC + CDELT storage included; a night that is
/// not East-left is mirrored, an unsolved one is left as it is. Cases translated from
/// `internal/fits/wcs_test.go` `TestHeader_CDDeterminant`.
@Suite("Group parity — det(CD) sign and the flip decision")
struct ParityNormaliserTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let cards: [(String, String)]
    let want: GroupParity
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    // Real Siril 1.4.3 solve of the primary rig: PC a proper rotation, CDELT1 < 0.
    Case(
      name: "siril PC+CDELT, primary rig East-left",
      cards: [
        ("CDELT1", "-0.000295504"), ("CDELT2", "0.000295525"), ("PC1_1", "0.0912"),
        ("PC1_2", "-0.9958"), ("PC2_1", "0.9958"), ("PC2_2", "0.0911"),
      ],
      want: .eastLeft),
    // Both CDELT positive but a reflection folded into PC: CDELT alone would read it wrong.
    Case(
      name: "reflection hidden in PC matrix",
      cards: [
        ("CDELT1", "0.0003"), ("CDELT2", "0.0003"), ("PC1_1", "1"), ("PC1_2", "0"),
        ("PC2_1", "0"), ("PC2_2", "-1"),
      ],
      want: .eastLeft),
    Case(
      name: "mirrored frame, positive CDELT1, PC identity",
      cards: [("CDELT1", "0.0003"), ("CDELT2", "0.0003")], want: .mirrored),
    Case(
      name: "explicit CD matrix, East-left",
      cards: [("CD1_1", "-0.0003"), ("CD1_2", "0"), ("CD2_1", "0"), ("CD2_2", "0.0003")],
      want: .eastLeft),
    Case(
      name: "explicit CD matrix takes precedence over CDELT",
      cards: [
        ("CD1_1", "0.0003"), ("CD1_2", "0"), ("CD2_1", "0"), ("CD2_2", "0.0003"),
        ("CDELT1", "-1"), ("CDELT2", "1"),
      ],
      want: .mirrored),
    Case(name: "no WCS at all", cards: [("GAIN", "300")], want: .unknown),
    Case(
      name: "degenerate zero determinant",
      cards: [("CDELT1", "0.0003"), ("CDELT2", "0"), ("PC1_1", "1"), ("PC2_2", "1")],
      want: .unknown),
  ]

  @Test("det(CD) sign gives the parity; only a mirrored night is flipped", arguments: cases)
  func testDetCDSignAndFlipDecision(_ example: Case) throws {
    let cards = Dictionary(uniqueKeysWithValues: example.cards)
    let data = TestFITS.header(width: 1, height: 1, planes: 1, cards: cards)
    let parity = GroupParity(determinant: try FITSFile.parse(data).header.cdDeterminant)
    #expect(parity == example.want)
    #expect(parity.needsMirror == (example.want == .mirrored))
  }
}
