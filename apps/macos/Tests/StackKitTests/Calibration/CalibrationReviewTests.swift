import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Behaviour fixed during the 0047 review, beyond the legacy engine: what is applied is what is
/// shown (R2), and a library master is reused only when it provably is the one asked for.
@Suite("Calibration review fixes — applied equals shown")
struct CalibrationReviewTests {
  typealias Fixtures = CalibrationFixtures

  @Test("excluding the bias of a -opt dark drops that dark too: it cannot be scaled without it")
  func testMatcher_excludedBiasDropsOptimizedDark() {
    let light = Fixtures.light("L", exposureMs: 60000, tempC: -15)
    let base = CalibrationMatcher.match(LightRef(key: light), masters: Fixtures.standard)
    #expect(base.darkOptimize)
    let selection = CalibrationMatcher.match(
      LightRef(key: light), masters: Fixtures.standard,
      excluded: [CalibrationMatcher.suggestionID(light, role: .bias)])
    #expect(selection.bias == nil)
    #expect(selection.dark == nil)
    #expect(!selection.darkOptimize)
    #expect(
      selection.notes.contains(
        "dark skipped — the 300000ms dark cannot be scaled to 60000ms lights without the bias"))
  }

  @Test("a library master stacked with another recipe is not reused", .scratchDirectory)
  func testMasterBuilder_recipeMustMatch() async throws {
    let root = try ScratchDirectory.url
    let library = root.appendingPathComponent("library")
    let set = try MasterBuilderTests.darkSet(frames: 3, in: root)
    _ = try await MasterBuilder(runner: RecordingSiril().runner).build(
      MasterBuilderTests.inventory([set]), into: library, work: root.appendingPathComponent("w1"),
      publish: .atomic(runID: "a"))
    let indexed = try CalibrationLibrary(folder: library).scan().compactMap(
      MasterBuilderTests.libraryMaster)

    var recipes = MasterRecipes()
    recipes.dark = StackOptions(combine: .median, normalization: .none)
    let other = RecordingSiril()
    let result = try await MasterBuilder(runner: other.runner, recipes: recipes).build(
      MasterBuilderTests.inventory([set]), into: library, work: root.appendingPathComponent("w2"),
      publish: .atomic(runID: "b"), library: indexed)
    #expect(other.calls.count == 1)
    #expect(result.masters.first?.path.contains("_s") == true)
  }

  @Test("a publish that fails leaves no proof for the frames it did not publish", .scratchDirectory)
  func testMasterBuilder_failedPublishLeavesNoProof() async throws {
    let root = try ScratchDirectory.url
    let library = root.appendingPathComponent("library")
    let name = "master_DARK_60000ms_g100o10_b1_-10C"
    let first = try MasterBuilderTests.darkSet(frames: 3, in: root)
    _ = try await MasterBuilder(runner: RecordingSiril().runner).build(
      MasterBuilderTests.inventory([first]), into: library, work: root.appendingPathComponent("w1"),
      publish: .atomic(runID: "a"))
    // The published master is replaced by a folder the move cannot overwrite.
    let final = library.appendingPathComponent("\(name).fits")
    try FileManager.default.removeItem(at: final)
    try FileManager.default.createDirectory(
      at: final.appendingPathComponent("blocker"), withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: final.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: final.path)
    }

    let second = try MasterBuilderTests.darkSet(
      frames: 2, in: root.appendingPathComponent("second"))
    let result = try await MasterBuilder(runner: RecordingSiril().runner).build(
      MasterBuilderTests.inventory([second]), into: library,
      work: root.appendingPathComponent("w2"),
      publish: .atomic(runID: "b"))
    #expect(result.masters.isEmpty)
    #expect(!PoolSignature.proves(master: final.path, builtFrom: second.frames.map(\.path)))
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: library.path).allSatisfy {
        !$0.hasPrefix(".tmp_")
      })
  }

  @Test(
    "the preview reuses a library master only when its .sig proves the same frames",
    .scratchDirectory)
  func testCalibrationPreview_reuseNeedsProof() throws {
    let root = try ScratchDirectory.url
    let set = try MasterBuilderTests.darkSet(frames: 3, in: root)
    let inventory = MasterBuilderTests.inventory([set])
    let masterPath = root.appendingPathComponent("lib/master_DARK_60000ms_g100o10_b1_-10C.fits")
    try FileManager.default.createDirectory(
      at: masterPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("master".utf8).write(to: masterPath)
    var library = Fixtures.master(
      .dark, path: masterPath.path, exposureMs: 60000, gain: 100, offset: 10, tempC: -10, frames: 3,
      fromLibrary: true)
    library.hasTemp = true

    let unproven = CalibrationPreview.candidates(inventory: inventory, library: [library])
    #expect(unproven.count == 2)
    #expect(unproven.contains { $0.path.isEmpty })

    try Data(
      PoolSignature.format(hash: PoolSignature.of(set.frames.map(\.path)), frameCount: 3).utf8
    )
    .write(to: URL(fileURLWithPath: PoolSignature.sidecar(of: masterPath.path)))
    let proven = CalibrationPreview.candidates(inventory: inventory, library: [library])
    #expect(proven.map(\.path) == [masterPath.path])
  }
}
