import Foundation
import StackKit
import TestSupport
import Testing

/// The port against the legacy engine's own `inventory.json` (card 0044 oracle cases (a), (b)),
/// from committed headers rebuilt into FITS files: runs everywhere, CI included. The real `in/`
/// frames and the M31 cases are `LiveInventoryOracleTests`.
@Suite("Inventory oracle — the legacy inventory.json of the synthetic cases")
struct InventoryOracleTests {
  static func recorded(_ oracle: OracleCase) throws -> InventoryJSON.Object {
    let data = try Data(contentsOf: oracle.directory.appendingPathComponent("inventory.json"))
    return try (JSONSerialization.jsonObject(with: data) as? InventoryJSON.Object).unwrapped(
      "inventory.json")
  }

  /// Scans `roots` in the case's timezone and compares with its recorded inventory.
  static func differences(
    _ oracle: OracleCase, roots: [URL], replacing pairs: [(String, String)]
  ) throws -> [String] {
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let inventory = try InventoryBuilder(timeZone: zone).scan(paths: roots.map(\.path))
    let normalize = { (text: String) in
      pairs.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
    return InventoryJSON.differences(
      recorded: try recorded(oracle), actual: InventoryJSON.object(inventory, normalize: normalize))
  }

  @Test(
    "sets, counts, filters, nights, verdicts and warnings equal the recorded inventory",
    .scratchDirectory, arguments: ["golden-single-night", "golden-two-night"])
  func testMatchesRecordedInventory(name: String) throws {
    let oracle = try OracleFixtureTests.committedCase(name)
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let input = root.appendingPathComponent("in")
    try HeaderFixture.load(name).materialize(under: input)
    let differences = try Self.differences(
      oracle, roots: [input], replacing: [(root.path, "<ROOT>")])
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
  }

  @Test(
    "the comparison is not vacuous: one changed field, set or warning is reported",
    .scratchDirectory)
  func testMatchesRecordedInventory_detectsChanges() throws {
    let oracle = try OracleFixtureTests.committedCase("golden-single-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    try HeaderFixture.load("golden-single-night").materialize(
      under: root.appendingPathComponent("in"))
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let inventory = try InventoryBuilder(timeZone: zone).scan(paths: [
      root.appendingPathComponent("in").path
    ])
    let normalize = { (text: String) in text.replacingOccurrences(of: root.path, with: "<ROOT>") }
    let recorded = try Self.recorded(oracle)

    var filter = inventory
    filter.frames[0].gain += 1
    var sets = inventory
    sets.sets.removeLast()
    var warned = inventory
    warned.warnings = ["extra"]
    for changed in [filter, sets, warned] {
      #expect(
        !InventoryJSON.differences(
          recorded: recorded, actual: InventoryJSON.object(changed, normalize: normalize)
        ).isEmpty)
    }
    #expect(
      InventoryJSON.differences(
        recorded: recorded, actual: InventoryJSON.object(inventory, normalize: normalize)
      ).isEmpty)
  }
}
