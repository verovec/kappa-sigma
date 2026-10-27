import Foundation
import ProcessKit
import Testing

extension ProfileTests {
  @Test("the dual-band profile ships colour calibration off, with its why in both languages")
  func testDualbandProfileDisablesColourCalibrationWithWhy() throws {
    let registry = try ProcessRegistry.standard()
    let profile = try #require(
      try ProfileLibrary.builtins(registry: registry).first { $0.id == "emission-osc-dualband" })
    let step = try #require(
      profile.steps.first { $0.recipe.processID == ColourCalibrationProcess.id })
    #expect(step.values["enabled"] == .flag(false))
    let why = try #require(step.why["enabled"])
    #expect(!why.english.isEmpty && !why.french.isEmpty && why.english != why.french)
    #expect(!step.recipe.runsTool(as: ColourCalibrationProcess.self), "off: no tool needed")
    let ids = profile.steps.map(\.recipe.processID)
    let colour = try #require(ids.firstIndex(of: ColourCalibrationProcess.id))
    let stretch = try #require(ids.firstIndex(of: StretchProcess.id))
    #expect(colour < stretch, "on linear data")
  }
}

extension ProfileTests {
  @Test(
    "card 0140: a recipe naming its sensor and filter keeps them; one naming none loads unset",
    arguments: [
      (#"[{"id": "sensor", "value": "Sony IMX571"}, {"id": "filter", "value": "UV/IR Block"}]"#,
       "Sony IMX571", "UV/IR Block"),
      (#"[{"id": "enabled", "value": true}]"#, "", ""),
    ])
  func testColourCalibrationNamesInRecipes(params: String, sensor: String, filter: String) throws {
    let json = #"{"schemaVersion": 1, "process": "colour-calibration", "params": "# + params + "}"
    let loaded = try Recipe.load(
      Data(json.utf8), registry: try ProcessRegistry([ColourCalibrationProcess.self]))
    #expect(loaded.warnings.isEmpty)
    #expect(loaded.params.choice("sensor") == sensor && loaded.params.choice("filter") == filter)
    let unchosen = ColourCalibrationProcess.unchosen(loaded.params, layerIDs: ["RGB"])
    #expect(unchosen == (sensor.isEmpty ? ColourCalibrationProcess.oscNames : []))
  }
}
