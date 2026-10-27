import Foundation
import ProcessKit
import Testing

@Suite("ParamSet: typed parameters with bounds, units, levels; clamped, ordered, Codable")
struct ParamSetTests {
  static let schema = ParamSchema([
    ParamSpec(id: "gain", title: "Gain", unit: .none, level: .simple, number: 1, in: 0...4),
    ParamSpec(id: "radius", title: "Radius", unit: .px, level: .advanced, number: 2, in: 0...64),
    ParamSpec(
      id: "opacity", title: "Opacity", unit: .opacity, level: .simple, number: 1, in: 0...1),
    ParamSpec(id: "linked", title: "Linked", level: .advanced, flag: false),
    ParamSpec(
      id: "curve", title: "Curve", level: .simple, choice: "mtf", of: ["mtf", "ghs", "asinh"]),
  ])

  @Test(
    "a number is clamped into its bounds; NaN, ±Inf, a wrong kind or an unknown id is refused",
    arguments: [
      ("gain", ParamValue.number(2.5), ParamValue.number(2.5)),
      ("gain", .number(9), .number(4)),
      ("radius", .number(-3), .number(0)),
      ("opacity", .number(1.5), .number(1)),
      ("linked", .flag(true), .flag(true)),
      ("curve", .choice("ghs"), .choice("ghs")),
    ])
  func testClamp(id: String, value: ParamValue, expected: ParamValue) throws {
    var params = ParamSet(schema: Self.schema)
    try params.set(id, value)
    #expect(params[id] == expected)
  }

  @Test(
    "refused values leave the set unchanged",
    arguments: [
      ("gain", ParamValue.number(.nan)),
      ("gain", .number(.infinity)),
      ("gain", .flag(true)),
      ("curve", .choice("lanczos")),
      ("unknown", .number(1)),
    ])
  func testRefused(id: String, value: ParamValue) {
    var params = ParamSet(schema: Self.schema)
    #expect(throws: ParamError.self) { try params.set(id, value) }
    #expect(params == ParamSet(schema: Self.schema))
  }

  @Test("defaults in schema order; JSON round trip keeps order and values")
  func testClampAndCodable() throws {
    var params = ParamSet(schema: Self.schema)
    #expect(params.ids == ["gain", "radius", "opacity", "linked", "curve"])
    #expect(params.number("gain") == 1 && params.flag("linked") == false)
    #expect(params.choice("curve") == "mtf")
    try params.set("radius", .number(7.25))
    try params.set("curve", .choice("asinh"))

    let json = try JSONEncoder().encode(params)
    let text = try #require(String(data: json, encoding: .utf8))
    #expect(
      text.range(of: "gain")?.lowerBound ?? text.endIndex < text.range(of: "curve")?.lowerBound
        ?? text.startIndex)
    // Stored values come back through the schema, never as an unvalidated set.
    let stored = try JSONDecoder().decode([ParamSet.Entry].self, from: json)
    let (decoded, rejected) = ParamSet.loading(stored, onto: Self.schema)
    #expect(decoded == params && rejected.isEmpty)
    #expect(decoded.ids == params.ids)
  }

  @Test("a schema with a duplicate id stops the process (a programming error)")
  func testDuplicateIdIsAnInvariant() async {
    await #expect(processExitsWith: .failure) {
      _ = ParamSchema([
        ParamSpec(id: "a", title: "A", level: .simple, flag: false),
        ParamSpec(id: "a", title: "A", level: .simple, flag: true),
      ])
    }
  }

  @Test("loading values onto a schema clamps them and reports what it could not use")
  func testApplyingDecodedValues() throws {
    let stored = [
      ParamSet.Entry(id: "gain", value: .number(12)), ParamSet.Entry(id: "zoom", value: .number(1)),
      ParamSet.Entry(id: "linked", value: .number(1)),
    ]
    let (params, rejected) = ParamSet.loading(stored, onto: Self.schema)
    #expect(params.number("gain") == 4)
    #expect(params.flag("linked") == false)
    #expect(rejected.map(\.id) == ["zoom", "linked"])
  }

  @Test(
    "display rule: simple by default, a promoted advanced param shows, the disclosure shows all",
    arguments: [
      (false, Set<String>(), ["gain", "opacity", "curve"]),
      (false, Set(["radius"]), ["gain", "radius", "opacity", "curve"]),
      (true, Set<String>(), ["gain", "radius", "opacity", "linked", "curve"]),
    ] as [(Bool, Set<String>, [String])])
  func testLevelDisplayRule(disclosed: Bool, promoted: Set<String>, visible: [String]) {
    #expect(Self.schema.visible(disclosed: disclosed, promoted: promoted).map(\.id) == visible)
  }
}
