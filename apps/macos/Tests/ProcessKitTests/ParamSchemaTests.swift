import ProcessKit
import Testing

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
