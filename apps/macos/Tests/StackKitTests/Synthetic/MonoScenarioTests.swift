import FilterKit
import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0142: mono and one-shot-colour rigs this Mac has no capture of, end to end through the
/// scan, the lanes, the emitted Siril scripts and the bundle — on synthetic frames generated at
/// run time (`SyntheticCapture`), Siril played by `PipelineSiril` (the live suite runs it).
@Suite("Mono scenarios — synthetic captures through the inventory, lanes, scripts and bundle")
struct MonoScenarioTests {
  /// What one scenario must give.
  struct Expected: Sendable {
    let colorModel: ColorModel
    /// Light sets: filter, exposure (s), clip filter.
    let lights: [String]
    let lanes: [String]
    /// Bundle layers `id:role`, in the bundle's order (the fake Siril's masters are 1-plane, so
    /// the OSC clip lane is not split into its lines here: the live suite checks it).
    let layers: [String]
    let notes: [String]
  }

  static let expected: [SyntheticCapture.Scenario: Expected] = [
    .lrgbHa: Expected(
      colorModel: .mono,
      lights: [
        "B 120 unknown", "G 120 unknown", "Ha 120 unknown", "L 120 unknown", "R 120 unknown",
      ],
      lanes: ["B", "G", "Ha", "L", "R"],
      layers: ["L:lum", "R:red", "G:green", "B:blue", "Ha:line"],
      notes: [
        "Ha: continuum scale not fitted — Ha/R: reference too dark/flat to calibrate the "
          + "continuum (P85=5e+02)"
      ]),
    .sho: Expected(
      colorModel: .mono, lights: ["Ha 120 unknown", "OIII 120 unknown", "SII 120 unknown"],
      lanes: ["Ha", "OIII", "SII"], layers: ["Ha:line", "OIII:line", "SII:line"],
      notes: [
        "Ha: continuum scale not fitted — no broadband channel (R/L) to estimate the continuum "
          + "from",
        "OIII: continuum scale not fitted — no broadband channel (G/B/L) to estimate the continuum "
          + "from",
        "SII: continuum scale not fitted — no broadband channel (R/L) to estimate the continuum "
          + "from",
        "combined = Ha alone (mono: no colour composite to build)",
      ]),
    .lOnly: Expected(
      colorModel: .mono, lights: ["L 120 unknown"], lanes: ["L"], layers: ["L:lum"],
      notes: ["combined = L alone (mono: no colour composite to build)"]),
    .oscSIIOIII: Expected(
      colorModel: .osc, lights: ["RGB 120 broadband", "RGB 300 dualbandSII"],
      lanes: ["RGB", "RGB-dualband-sii"], layers: ["RGB:rgb"],
      notes: [
        "dualband-sii lane split skipped, finishing on the colour base alone: colour master has 1 "
          + "plane(s), need 3 to separate the two lines"
      ]),
  ]

  /// A scenario scanned as the import does it: a default scan, then the user's clip filters by
  /// set id (`InspectOverrides`), then the run with `siril`.
  struct Run {
    let root: URL
    let inventory: Inventory
    let lanes: [String]
    let siril: PipelineSiril
    let result: PreprocessResult
  }

  static func run(_ scenario: SyntheticCapture.Scenario) async throws -> Run {
    let root = try ScratchDirectory.url
    try SyntheticCapture(scenario).write(under: root.appendingPathComponent("in"))
    let inventory = try scan(scenario, root: root)
    let siril = PipelineSiril()
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/SYNTH/R1"),
      work: root.appendingPathComponent("work/run_R1"), runID: "R1")
    let preprocessor = Preprocessor(tools: PreprocessorTests.tools(siril))
    let result = try await preprocessor.perform(request) { _ in }
    return Run(
      root: root, inventory: inventory,
      lanes: try Preprocessor.plan(inventory).channels.keys.sorted(), siril: siril,
      result: result)
  }

  static func scan(_ scenario: SyntheticCapture.Scenario, root: URL) throws -> Inventory {
    let builder = InventoryBuilder(timeZone: try #require(TimeZone(identifier: "UTC")))
    let path = root.appendingPathComponent("in").path
    var overrides = InspectOverrides()
    for set in try builder.scan(paths: [path]).sets where set.key.type == .light {
      if let clip = scenario.clips[set.key.exposureMs / 1000] {
        overrides.filterSets[set.key.id] = clip
      }
    }
    return try builder.scan(paths: [path], overrides: overrides)
  }

  @Test(
    "testInventory: the colour model, the light sets and their lanes",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testInventory(scenario: SyntheticCapture.Scenario) async throws {
    let expected = try #require(Self.expected[scenario])
    let root = try ScratchDirectory.url
    try SyntheticCapture(scenario).write(under: root.appendingPathComponent("in"))
    let inventory = try Self.scan(scenario, root: root)
    #expect(inventory.colorModel == expected.colorModel)
    let lights = inventory.sets.filter { $0.key.type == .light }.map { set in
      "\(set.key.filter) \(set.key.exposureMs / 1000) \(LightRef(set, in: inventory).filterSet)"
    }
    #expect(lights.sorted() == expected.lights)
    #expect(try Preprocessor.plan(inventory).channels.keys.sorted() == expected.lanes)
    #expect(inventory.warnings.isEmpty)
  }

  @Test(
    "testBundleLayers: every scenario ends on a bundle and a combined image, with its notes",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testBundleLayers(scenario: SyntheticCapture.Scenario) async throws {
    let expected = try #require(Self.expected[scenario])
    let run = try await Self.run(scenario)
    let bundle = try #require(run.result.bundle)
    #expect(bundle.layers.map { "\($0.id):\($0.role)" } == expected.layers)
    #expect(bundle.colorModel == expected.colorModel)
    #expect(run.result.combinedPath?.hasSuffix("/combined.fits") == true)
    #expect(run.result.notes == expected.notes)
  }

  @Test(
    "testScripts: the emitted Siril scripts equal the committed snapshot (RECORD=1 rewrites it)",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testScripts(scenario: SyntheticCapture.Scenario) async throws {
    let run = try await Self.run(scenario)
    let text = run.siril.calls.enumerated().map { index, call in
      "### \(index + 1) \(call.directory.lastPathComponent)\n"
        + call.script.replacingOccurrences(of: run.root.path, with: "<ROOT>")
    }.joined(separator: "\n")
    let name = "Fixtures/synthetic/\(scenario.rawValue).ssf.txt"
    if ProcessInfo.processInfo.environment["RECORD"] == "1" {
      let package = URL(fileURLWithPath: try ModuleBoundary.packageRoot(from: #filePath))
      let file = package.appendingPathComponent("Tests/StackKitTests/\(name)")
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try text.write(to: file, atomically: true, encoding: .utf8)
    }
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil))
    let recorded = try String(contentsOf: url, encoding: .utf8)
    #expect(recorded.split(separator: "\n") == text.split(separator: "\n"))
  }
}
