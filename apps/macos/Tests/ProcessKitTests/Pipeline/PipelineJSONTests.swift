import Foundation
import ProcessKit
import Testing

/// Pipelines as JSON (card 0059): versioned, recipes inside, unknown keys and clamps warn.
@Suite("Pipeline JSON — round trip, warnings, refusals")
struct PipelineJSONTests {
  @Test("JSON round trip; unknown keys, parameters and clamped values are warnings")
  func testRoundTripAndUnknownKeyWarns() throws {
    let registry = try ProcessRegistry([DummyGain.self])
    let pipeline = Pipeline(
      name: "M31 v9",
      steps: [try PipelineDiffTests.step(2), try PipelineDiffTests.step(3, .stop, locked: true)])
    let loaded = try Pipeline.load(pipeline.json(), registry: registry)
    #expect(loaded.pipeline == pipeline)
    #expect(loaded.warnings.isEmpty)

    let json = """
      {"schemaVersion": 1, "name": "M31", "author": "PO",
       "steps": [{"recipe": {"schemaVersion": 1, "process": "dummy-gain",
                             "params": [{"id": "gain", "value": 12}, {"id": "colour", "value": 1}]},
                  "mode": "auto", "locked": false, "note": "x"}]}
      """
    let warned = try Pipeline.load(Data(json.utf8), registry: registry)
    #expect(
      warned.warnings == [
        "unknown key author ignored",
        "step 1: unknown key note ignored",
        "step 1: parameter gain clamped from 12.0 to 8.0",
        "step 1: parameter colour ignored: not in dummy-gain",
      ])
    #expect(warned.pipeline.steps.first?.recipe.params.first?.value == .number(8))
  }

  @Test("a batch tool's step loads with its schema; a step error names its step")
  func testBatchStepAndStepErrors() throws {
    let registry = try ProcessRegistry([DummyGain.self])
    let starnet = ParamSchema([
      ParamSpec(
        id: "stride", title: "Stride", unit: .none, level: .advanced, number: 256, in: 64...512)
    ])
    var params = ParamSet(schema: starnet)
    try params.set("stride", .number(128))
    let pipeline = Pipeline(
      name: "M31",
      steps: [
        try PipelineDiffTests.step(2),
        PipelineStep(recipe: Recipe(processID: "starnet", params: params)),
      ])
    let loaded = try Pipeline.load(pipeline.json(), registry: registry, batch: ["starnet": starnet])
    #expect(loaded.pipeline == pipeline)
    #expect(throws: PipelineFileError.self) {
      try Pipeline.load(pipeline.json(), registry: registry)
    }
    do {
      _ = try Pipeline.load(
        Data(Self.oneStep(process: "nope", mode: "auto").utf8), registry: registry)
      Issue.record("an unknown process loaded")
    } catch PipelineFileError.step(let number, _) {
      #expect(number == 1)
    }
  }

  @Test("locked must be a JSON boolean, not 1 or 0")
  func testLockedIsBoolean() throws {
    let registry = try ProcessRegistry([DummyGain.self])
    let json = Self.oneStep(process: "dummy-gain", mode: "auto")
      .replacingOccurrences(of: #""locked": false"#, with: #""locked": 1"#)
    #expect(throws: PipelineFileError.self) {
      try Pipeline.load(Data(json.utf8), registry: registry)
    }
  }

  /// A pipeline file of one step running `process` in `mode`.
  static func oneStep(process: String, mode: String) -> String {
    #"{"schemaVersion": 1, "name": "M31", "steps": [{"recipe": {"schemaVersion": 1, "process": ""#
      + process + #"", "params": []}, "mode": ""# + mode + #"", "locked": false}]}"#
  }

  @Test("a newer format, an unknown process or a bad mode is refused, never guessed")
  func testRefusals() throws {
    let registry = try ProcessRegistry([DummyGain.self])
    for json in [
      #"{"schemaVersion": 2, "name": "M31", "steps": []}"#,
      Self.oneStep(process: "nope", mode: "auto"),
      Self.oneStep(process: "dummy-gain", mode: "later"),
    ] {
      #expect(throws: (any Error).self) { try Pipeline.load(Data(json.utf8), registry: registry) }
    }
  }
}
