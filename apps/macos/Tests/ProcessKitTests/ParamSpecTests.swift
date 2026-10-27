import ProcessKit
import Testing

/// A layer parameter (card 0138): its value is a layer token — well-formed by grammar, named by
/// the bundle — carried as a `.choice` on the wire, so recipes and profiles do not change.
@Suite("ParamSpec.Kind.layer — a layer token, well-formed by grammar, named by the bundle")
struct ParamSpecTests {
  struct Token: CustomTestStringConvertible, Sendable {
    let token: String
    var allowsNone = true
    var allowsProduct = true
    let accepted: Bool
    var testDescription: String {
      "\(token.debugDescription) none:\(allowsNone) product:\(allowsProduct) → \(accepted)"
    }
  }

  static let tokens: [Token] = [
    Token(token: "Ha", accepted: true),
    Token(token: "RGB.r", accepted: true),
    Token(token: "Ha*OIII", accepted: true),
    Token(token: "NII-custom", accepted: true),
    Token(token: "none", accepted: true),
    Token(token: "none", allowsNone: false, accepted: false),
    Token(token: "", accepted: false),
    Token(token: "RGB.x", accepted: true),  // a custom layer named so; the bundle judges
    Token(token: "a b", accepted: true),  // a FITS filter name kept verbatim
    Token(token: " a", accepted: false),
    Token(token: "a ", accepted: false),
    Token(token: "*Ha", accepted: false),
    Token(token: "none*Ha", accepted: false),
    Token(token: "RGB.r*Ha", accepted: false),
    Token(token: "Ha*Ha", accepted: false),
    Token(token: "Ha*OIII", allowsNone: false, accepted: true),
    Token(token: "Ha*", accepted: false),
    Token(token: "Ha*OIII*SII", accepted: false),
    Token(token: "Ha*OIII", allowsProduct: false, accepted: false),
  ]

  @Test("testLayerKind_validates", arguments: tokens)
  func testLayerKind_validates(row: Token) throws {
    let spec = ParamSpec(
      id: "rSource", title: "Red", level: .simple, layer: "RGB.r", allowsNone: row.allowsNone,
      allowsProduct: row.allowsProduct)
    if row.accepted {
      #expect(try spec.validated(.choice(row.token)) == .choice(row.token))
    } else {
      #expect(throws: ParamError.self) { try spec.validated(.choice(row.token)) }
    }
    #expect(throws: ParamError.self) { try spec.validated(.number(1)) }
  }

  @Test("the default is a layer token on the wire; a malformed default is a schema problem")
  func testLayerKind_default() {
    let spec = ParamSpec(
      id: "lSource", title: "Luminance", level: .simple, layer: "none", allowsNone: true,
      allowsProduct: false)
    #expect(spec.defaultValue == .choice("none"))
    #expect(ParamSchema([spec]).problems.isEmpty)
    let malformed = ParamSpec(
      id: "lSource", title: "Luminance", level: .simple, layer: "Ha*", allowsNone: true,
      allowsProduct: true)
    #expect(ParamSchema([malformed]).problems == ["lSource: default Ha* is not a layer token"])
  }
}
