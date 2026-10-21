import Foundation
import ProcessKit
import Testing

/// The `points` parameter kind (curves, card 0053): validated like a number, encoded as JSON.
@Suite("Points parameters: control points sorted, clamped and round-tripped")
struct ParamPointsTests {
  static let spec = ParamSpec(
    id: "curve", title: "Curve", level: .simple, points: [CurvePoint(0, 0), CurvePoint(1, 1)],
    maxCount: 4)
  static let schema = ParamSchema([spec])

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let input: [CurvePoint]
    let expected: [CurvePoint]?
    var testDescription: String { name }
  }

  @Test(
    "points are sorted by x and clamped into [0, 1]; too few or many, NaN or a repeated x refused",
    arguments: [
      Case(
        name: "kept", input: [CurvePoint(0, 0), CurvePoint(0.5, 0.6), CurvePoint(1, 1)],
        expected: [CurvePoint(0, 0), CurvePoint(0.5, 0.6), CurvePoint(1, 1)]),
      Case(
        name: "sorted", input: [CurvePoint(1, 1), CurvePoint(0, 0.1)],
        expected: [CurvePoint(0, 0.1), CurvePoint(1, 1)]),
      Case(
        name: "clamped", input: [CurvePoint(-0.2, -1), CurvePoint(1.5, 2)],
        expected: [CurvePoint(0, 0), CurvePoint(1, 1)]),
      Case(name: "one point", input: [CurvePoint(0.5, 0.5)], expected: nil),
      Case(
        name: "five points", input: (0..<5).map { CurvePoint(Double($0) / 4, 0) }, expected: nil),
      Case(name: "NaN", input: [CurvePoint(0, .nan), CurvePoint(1, 1)], expected: nil),
      Case(
        name: "repeated x", input: [CurvePoint(0.5, 0), CurvePoint(0.5, 1), CurvePoint(1, 1)],
        expected: nil),
    ])
  func testValidation(_ example: Case) throws {
    var params = ParamSet(schema: Self.schema)
    if let expected = example.expected {
      try params.set("curve", .points(example.input))
      #expect(params.points("curve") == expected)
    } else {
      #expect(throws: ParamError.self) { try params.set("curve", .points(example.input)) }
      #expect(params.points("curve") == [CurvePoint(0, 0), CurvePoint(1, 1)])
    }
  }

  @Test("points encode as [[x, y], …] and decode back; other kinds still decode as before")
  func testJSONRoundTrip() throws {
    let value = ParamValue.points([CurvePoint(0, 0), CurvePoint(0.25, 0.5)])
    let data = try JSONEncoder().encode(value)
    #expect(String(bytes: data, encoding: .utf8) == "[[0,0],[0.25,0.5]]")
    #expect(try JSONDecoder().decode(ParamValue.self, from: data) == value)
    for (json, kind) in [
      ("1.5", ParamValue.number(1.5)), ("true", .flag(true)), ("\"a\"", .choice("a")),
    ] {
      #expect(try JSONDecoder().decode(ParamValue.self, from: Data(json.utf8)) == kind)
    }
  }

  @Test("a recipe whose curve validation changes is loaded with a warning, never silently")
  func testRecipeWarnsOnChangedCurve() throws {
    let json = """
      {"schemaVersion": 1, "process": "curves",
       "params": [{"id": "rgb", "value": [[1.2, 0.9], [-0.1, 0], [0.5, 0.5]]},
                  {"id": "red", "value": [[0, 0], [1, 1]]}]}
      """
    let loaded = try Recipe.load(Data(json.utf8), registry: ProcessRegistry.standard())
    #expect(
      loaded.params.points("rgb") == [CurvePoint(0, 0), CurvePoint(0.5, 0.5), CurvePoint(1, 0.9)])
    #expect(loaded.warnings == ["parameter rgb: curve points clamped into [0, 1] or reordered"])
  }

  @Test("a curve point that is not an [x, y] pair skips that parameter, not the recipe")
  func testMalformedPointIsOneWarning() throws {
    let json = """
      {"schemaVersion": 1, "process": "curves",
       "params": [{"id": "luminance", "value": [[0, 0], [0.5], [1, 1]]},
                  {"id": "red", "value": [[0, 0], [0.5, 0.7], [1, 1]]}]}
      """
    let loaded = try Recipe.load(Data(json.utf8), registry: ProcessRegistry.standard())
    #expect(loaded.warnings == ["parameter luminance ignored: invalid value"])
    #expect(loaded.params.points("red").count == 3)
  }

  @Test("a schema whose default points would be changed by validation is invalid")
  func testInvalidDefault() {
    let bad = ParamSchema([
      ParamSpec(
        id: "curve", title: "Curve", level: .simple,
        points: [CurvePoint(1, 1), CurvePoint(0, 0)], maxCount: 4)
    ])
    #expect(bad.problems.count == 1)
    #expect(Self.schema.problems.isEmpty)
  }

  @Test("a number is refused for a points parameter, and points for a number")
  func testWrongKind() throws {
    var params = ParamSet(schema: Self.schema)
    #expect(throws: ParamError.wrongKind(id: "curve")) { try params.set("curve", .number(1)) }
    #expect(params.number("curve") == 0)
  }
}
