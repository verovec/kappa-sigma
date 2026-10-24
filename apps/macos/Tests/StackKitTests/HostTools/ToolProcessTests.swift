import Foundation
import StackKit
import Testing

@Suite("ToolProcess: the environment a host tool is started with (card 0124)")
struct ToolProcessTests {
  /// One override set and what the child must then see.
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let overrides: [String: String]
    let expected: [String]

    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(name: "none: the app's own (GraXpert's call)", overrides: [:], expected: []),
    Case(
      name: "a new key is added, the rest inherited", overrides: ["ASTROSTACK_PROBE": "0124"],
      expected: ["ASTROSTACK_PROBE=0124"]),
    Case(
      name: "an inherited key is replaced", overrides: ["HOME": "/override"],
      expected: ["HOME=/override"]),
  ]

  @Test("overrides are set over the app's environment", arguments: cases)
  func testToolProcess_runLines_environment(_ row: Case) async throws {
    let outcome = try await ToolProcess.runLines(
      "/usr/bin/env", arguments: [], environment: row.overrides
    ) { _ in }
    let lines = Set(outcome.log.split(separator: "\n").map(String.init))
    for line in row.expected { #expect(lines.contains(line), "\(line)") }
    let path = try #require(ProcessInfo.processInfo.environment["PATH"])
    #expect(lines.contains("PATH=\(path)"), "the rest is inherited")
  }
}
