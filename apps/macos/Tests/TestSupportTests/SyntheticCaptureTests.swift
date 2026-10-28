import Foundation
import TestSupport
import Testing

/// Card 0142: the synthetic captures are generated at run time, so they must be the same bytes
/// every time — the scripts and checksums the scenario tests pin depend on it.
@Suite("SyntheticCapture — deterministic frames of a seeded star field, per scenario")
struct SyntheticCaptureTests {
  @Test(
    "testDeterministic: two generations give identical bytes",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testDeterministic(scenario: SyntheticCapture.Scenario) throws {
    let root = try ScratchDirectory.url
    let first = try SyntheticCapture(scenario).write(under: root.appendingPathComponent("a"))
    let second = try SyntheticCapture(scenario).write(under: root.appendingPathComponent("b"))
    #expect(first.count == second.count && !first.isEmpty)
    for (one, two) in zip(first, second) {
      #expect(one.lastPathComponent == two.lastPathComponent)
      #expect(try Data(contentsOf: one) == Data(contentsOf: two), "\(one.lastPathComponent)")
    }
    let lights = first.filter { $0.path.contains("/lights/") }
    #expect(lights.count == scenario.filters.count * SyntheticCapture.lightsPerSet)
  }
}
