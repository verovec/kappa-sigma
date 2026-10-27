import Metal
import ProcessKit
import Testing

/// A GPU process leaving a choice unset: nothing would refuse its Apply, so the registry does.
struct UnsetChoiceGPUProcess: ImageProcess {
  static let id = "unset-gpu"
  static let title = "Unset"
  static let stage = ProcessStage.any
  static let schema = ParamSchema([
    ParamSpec(id: "c", title: "C", level: .simple, choice: "", of: ["a"], allowsUnset: true)
  ])
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }
  func render(_ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext) {
  }
}

/// Card 0140: a choice may start unset (« Choose… ») when its spec says so — the default is
/// then no option at all, never one picked for the user.
@Suite("ParamSchema: a choice unset by default only where its spec allows it")
struct ParamSchemaTests {
  @Test(
    "testChoiceAllowsUnsetDefault: an empty default is valid with allowsUnset, a problem without",
    arguments: [
      (true, [String]()),
      (false, ["sensor: default  not among its options"]),
    ])
  func testChoiceAllowsUnsetDefault(allowsUnset: Bool, problems: [String]) {
    let spec = ParamSpec(
      id: "sensor", title: "Sensor", level: .simple, choice: "", of: ["A", "B"],
      allowsUnset: allowsUnset)
    #expect(ParamSchema([spec]).problems == problems)
  }

  @Test("only a host-tool process may leave a choice unset: its Apply is where it is refused")
  func testUnsetChoiceNeedsHostTool() {
    #expect(
      ProcessRegistry.problems(of: UnsetChoiceGPUProcess.self) == [
        "has unset choices (c): only a host-tool process may"
      ])
    #expect(UnsetChoiceGPUProcess.unchosen(ParamSet(schema: UnsetChoiceGPUProcess.schema)).isEmpty)
  }

  @Test(
    "an unset choice takes an option, and goes back to unset only where it is allowed",
    arguments: [true, false])
  func testUnsetValue(allowsUnset: Bool) throws {
    let spec = ParamSpec(
      id: "sensor", title: "Sensor", level: .simple, choice: allowsUnset ? "" : "A",
      of: ["A", "B"], allowsUnset: allowsUnset)
    var params = ParamSet(schema: ParamSchema([spec]))
    try params.set("sensor", .choice("B"))
    #expect(params.choice("sensor") == "B")
    if allowsUnset {
      try params.set("sensor", .choice(""))
      #expect(params.choice("sensor").isEmpty)
    } else {
      #expect(throws: ParamError.unknownOption(id: "sensor", option: "")) {
        try params.set("sensor", .choice(""))
      }
    }
  }
}
