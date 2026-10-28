import ProcessKit
import Testing

/// A palette resolved against the layers present (card 0137): the legacy `resolvePalette` chain
/// (`palette.go:98-148`, `palette_test.go`), translated to the Swift palettes.
///
/// The Go natural (R, G, B filters, L optional) is the Swift LRGB template, or RGB without L;
/// the Swift natural is the one-shot-colour layer. Not translated: hargb (no
/// such palette: Hα enters by line injection), `isPaletteName` and the unknown name (the palette
/// is an enum), Foraxx's `$Ha$` substitution (its green is a source of the template).
@Suite("Palette — the fallback chain to what the layers allow")
struct PaletteTests {
  /// One row: what was asked, the layers present, what resolves and the words the reason holds.
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let requested: Palette
    let present: Set<String>
    let palette: Palette?
    var monoSource: String?
    var reason: [String] = []
    var testDescription: String { name }
  }

  static let cases = [
    // TestResolvePalette_NaturalDefault
    Case(
      name: "LRGB with every filter", requested: .lrgb, present: ["L", "R", "G", "B", "Ha"],
      palette: .lrgb),
    Case(
      name: "natural on a colour layer", requested: .natural, present: ["RGB", "Ha"],
      palette: .natural),
    // TestResolvePalette_HaRGB, its fallback: a missing line falls back to the broadband.
    Case(
      name: "HOO without OIII falls back to natural", requested: .hoo, present: ["RGB", "Ha"],
      palette: .natural, reason: ["HOO", "OIII", "Natural"]),
    // TestResolvePalette_Narrowband
    Case(name: "HOO", requested: .hoo, present: ["Ha", "OIII"], palette: .hoo),
    Case(name: "SHO", requested: .sho, present: ["SII", "Ha", "OIII"], palette: .sho),
    Case(name: "HOS", requested: .hos, present: ["SII", "Ha", "OIII"], palette: .hos),
    // TestResolvePalette_Foraxx
    Case(name: "Foraxx", requested: .foraxx, present: ["Ha", "OIII"], palette: .foraxx),
    // TestResolvePalette_FallbackChain
    Case(
      name: "SHO on L, R, G, B, Hα walks sho → hoo → natural → LRGB", requested: .sho,
      present: ["L", "R", "G", "B", "Ha"], palette: .lrgb, reason: ["SHO", "SII", "OIII", "LRGB"]),
    Case(
      name: "SHO on Hα alone ends mono", requested: .sho, present: ["Ha"], palette: nil,
      monoSource: "Ha", reason: ["SHO", "SII", "OIII", "Ha"]),
    // The broadband chain ends on the palette the layers spell before mono (one rule with the
    // combination's start, `Palette.spelled(by:)`).
    Case(
      name: "natural on Hα + OIII: HOO, as the combination starts", requested: .natural,
      present: ["Ha", "OIII"], palette: .hoo, reason: ["Natural", "RGB", "HOO"]),
    // TestResolvePalette_Mono, through the chain's end.
    Case(
      name: "LRGB without B: mono on L", requested: .lrgb, present: ["L", "R", "G"], palette: nil,
      monoSource: "L", reason: ["LRGB", "B", "L"]),
    Case(
      name: "LRGB on R, G, Hα: mono on Hα before R", requested: .lrgb, present: ["R", "G", "Ha"],
      palette: nil, monoSource: "Ha", reason: ["LRGB", "B", "Ha"]),
    // TestResolvePalette_NaturalDefault: natural without L is still R, G, B (the RGB template).
    Case(
      name: "LRGB on R, G, B without L falls back to RGB", requested: .lrgb,
      present: ["R", "G", "B", "Ha"], palette: .rgb, reason: ["LRGB", "L", "RGB"]),
    Case(name: "RGB", requested: .rgb, present: ["R", "G", "B"], palette: .rgb),
    Case(
      name: "natural on R, G, B walks natural → LRGB → RGB", requested: .natural,
      present: ["R", "G", "B"], palette: .rgb, reason: ["Natural", "RGB"]),
    // A colour layer passes through whatever was asked of it.
    Case(
      name: "LRGB on a colour bundle falls back to natural", requested: .lrgb,
      present: ["RGB", "Ha", "OIII"], palette: .natural, reason: ["LRGB", "Natural"]),
    Case(
      name: "nothing present", requested: .natural, present: [], palette: nil, reason: ["Natural"]),
  ]

  @Test("the fallback chain", arguments: cases)
  func testResolve_fallbackChain(_ row: Case) throws {
    let resolved = Palette.resolve(requested: row.requested, present: row.present)
    #expect(resolved.palette == row.palette)
    #expect(resolved.monoSource == row.monoSource)
    guard !row.reason.isEmpty else {
      #expect(resolved.reason == nil)
      return
    }
    let reason = try #require(resolved.reason)
    for word in row.reason { #expect(reason.contains(word), "\(word) in \(reason)") }
  }

  @Test("OIII as blue without a B filter is offered, never applied by the chain")
  func testOIIIAsBlue_isASuggestion() throws {
    let present: Set<String> = ["L", "R", "G", "OIII"]
    let suggestion = try #require(Palette.oiiiAsBlue(present: present))
    #expect(suggestion.paramID == "bSource")
    #expect(suggestion.value == .choice("OIII"))
    #expect(suggestion.reason.contains("OIII"))
    let resolved = Palette.resolve(requested: .lrgb, present: present)
    #expect(resolved.palette == nil && resolved.monoSource == "L")
    for present: Set<String> in [["L", "R", "G", "B", "OIII"], ["RGB", "OIII"], ["R", "G"]] {
      #expect(Palette.oiiiAsBlue(present: present) == nil)
    }
  }
}
