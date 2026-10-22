import Foundation
import ProcessKit
import Testing

extension PipelineJSONTests {
  /// Card 0092: a profile may carry a background-extraction step (a batch process, registered
  /// like any other) with the « why » of each value; its pipeline round-trips through JSON.
  @Test("testProfileLoadsBackgroundStepWithWhy")
  func testProfileLoadsBackgroundStepWithWhy() throws {
    let json = """
      {"schemaVersion": 1, "id": "test-bge", "object": "emission-nebula", "camera": "osc",
       "filters": ["dualband"], "examples": [], "title": {"en": "BGE", "fr": "BGE"},
       "preprocessing": {"mode": "nebula", "knobs": {}, "why": {}},
       "steps": [
         {"process": "channel-combination", "mode": "auto", "locked": false, "values": {},
          "why": {}},
         {"process": "background-extraction", "mode": "stop", "locked": false,
          "values": {"engine": "siril-rbf", "samples": 40},
          "why": {
            "engine": {"en": "Siril only on this machine.", "fr": "Siril seul sur cette machine."},
            "samples": {"en": "A finer gradient.", "fr": "Un gradient plus fin."}}}]}
      """
    let registry = try ProcessRegistry.standard()
    let profile = try Profile.load(Data(json.utf8), registry: registry)
    let step = try #require(profile.steps.last)
    #expect(step.recipe.processID == BackgroundExtractionProcess.id && step.mode == .stop)
    #expect(step.values == ["engine": .choice("siril-rbf"), "samples": .number(40)])
    #expect(step.why["engine"]?.french == "Siril seul sur cette machine.")
    #expect(step.why["samples"]?.english == "A finer gradient.")

    let loaded = try Pipeline.load(profile.pipeline.json(), registry: registry)
    #expect(loaded.warnings.isEmpty)
    #expect(loaded.pipeline.steps.last?.recipe == step.recipe)
  }
}
