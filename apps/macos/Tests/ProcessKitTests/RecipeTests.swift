import Foundation
import ProcessKit
import Testing

@Suite("Recipe: a process and its values as JSON, loaded across versions")
struct RecipeTests {
  static func registry() throws -> ProcessRegistry {
    try ProcessRegistry([DummyGain.self])
  }

  @Test("export then import gives the same process and values")
  func testRoundTrip() throws {
    var params = ParamSet(schema: DummyGain.schema)
    try params.set("gain", .number(2.5))
    let recipe = Recipe(processID: DummyGain.id, params: params)
    let loaded = try Recipe.load(try recipe.json(), registry: Self.registry())
    #expect(loaded.recipe == recipe && loaded.warnings.isEmpty)
    #expect(loaded.params == params)
  }

  @Test("a v1 recipe with an unknown key loads with a warning, not an error")
  func testExportImportAcrossVersions() throws {
    let json = """
      {"schemaVersion": 1, "process": "dummy-gain", "createdBy": "AstroStack 2.3",
       "params": [{"id": "gain", "value": 12}, {"id": "shift", "value": 3},
                  {"id": "sharpness", "value": 0.4}]}
      """
    let loaded = try Recipe.load(Data(json.utf8), registry: Self.registry())
    #expect(loaded.params.number("gain") == 8, "clamped into the schema's bounds")
    #expect(loaded.params.number("shift") == 3)
    #expect(loaded.warnings == [
      "unknown key createdBy ignored",
      "parameter sharpness ignored: not in dummy-gain",
    ])
  }

  @Test(
    "an unknown process, a newer schema or a malformed file is an error",
    arguments: [
      #"{"schemaVersion": 1, "process": "lanczos", "params": []}"#,
      #"{"schemaVersion": 2, "process": "dummy-gain", "params": []}"#,
      #"{"process": "dummy-gain"}"#,
      "not json",
    ])
  func testRefused(json: String) {
    #expect(throws: RecipeError.self) { try Recipe.load(Data(json.utf8), registry: Self.registry()) }
  }
}
