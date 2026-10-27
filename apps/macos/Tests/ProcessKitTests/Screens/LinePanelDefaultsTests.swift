import FilterKit
import ProcessKit
import Testing

/// The line processes read FilterKit's list (card 0133): every narrowband filter is a line with
/// panel defaults, and the schemas carry the same defaults as before the move.
@Suite("LinePanelDefaults — one entry per narrowband filter, the schemas' defaults unchanged")
struct LinePanelDefaultsTests {
  @Test("every narrowband filter has panel defaults", arguments: Filter.narrowband)
  func testEveryNarrowbandFilterHasDefaults(filter: Filter) {
    #expect(LinePanelDefaults.table[filter] != nil, "\(filter.rawValue) needs an entry")
  }

  @Test("the defaults table keys exactly the narrowband filters: no stray broadband row")
  func testTableKeysAreTheNarrowbandFilters() {
    #expect(Set(LinePanelDefaults.table.keys) == Set(Filter.narrowband))
  }

  @Test("the broadband reference layers are FilterKit's broadband filters, in order")
  func testBroadbandLayersComeFromFilterKit() {
    #expect(LineInjectionProcess.broadbandLayers == Filter.broadband.map(\.rawValue))
    #expect(LineInjectionProcess.broadbandLayers == ["L", "R", "G", "B"])
  }

  @Test("the lines are the narrowband filters, in display order, with their panel names")
  func testLinesProjectTheFilters() {
    #expect(EmissionLine.allCases.map(\.filter) == Filter.narrowband)
    #expect(EmissionLine.allCases.map(\.name) == ["Hα", "[OIII]", "[SII]"])
    #expect(EmissionLine.allCases.map(\.prefix) == ["ha", "oiii", "sii"])
    #expect(EmissionLine(.red) == nil)
    #expect(EmissionLine(.hydrogenAlpha)?.layerID == "Ha")
  }

  /// One row per line: the screen defaults (enabled, opacity, tint) and the injection shares.
  struct Row: CustomTestStringConvertible, Sendable {
    let prefix: String
    let enabled: Bool
    let opacity: Double
    let tint: String
    let shares: [Double]
    var testDescription: String { prefix }
  }

  static let rows = [
    Row(prefix: "ha", enabled: true, opacity: 0.85, tint: "red", shares: [1, 0, 0]),
    Row(prefix: "oiii", enabled: true, opacity: 0.78, tint: "teal", shares: [0, 0.5, 0.5]),
    Row(prefix: "sii", enabled: false, opacity: 0.6, tint: "gold", shares: [1, 0, 0]),
  ]

  @Test(
    "the screens and injection schemas keep the defaults of the enum they replace", arguments: rows)
  func testSchemaDefaultsUnchanged(row: Row) throws {
    let screens = EmissionScreensProcess.schema
    #expect(try #require(screens.spec(row.prefix + "Enabled")).kind == .flag(default: row.enabled))
    #expect(
      try #require(screens.spec(row.prefix + "Opacity")).kind
        == .number(default: row.opacity, bounds: 0...1))
    #expect(
      try #require(screens.spec(row.prefix + "Tint")).kind
        == .choice(default: row.tint, options: ScreenTint.allCases.map(\.rawValue)))
    let injection = LineInjectionProcess.schema
    for (plane, share) in zip(["Red", "Green", "Blue"], row.shares) {
      #expect(
        try #require(injection.spec(row.prefix + plane)).kind
          == .number(default: share, bounds: 0...1), "\(row.prefix)\(plane)")
    }
  }
}
