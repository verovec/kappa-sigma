import Foundation
import StackKit
import TestSupport
import Testing

/// `MasterBuilder` (`BuildMasters`, `BuildOrReuseMasters`, `buildOne`, `stackMasterSet`): the
/// scripts it hands Siril are the recorded ones, byte for byte; a master appears only complete.
@Suite("MasterBuilder — calibration sets into masters through Siril")
struct MasterBuilderTests {
  static func scan(_ name: String, under root: URL) throws -> Inventory {
    let input = root.appendingPathComponent("in")
    try HeaderFixture.load(name).materialize(under: input)
    let oracle = try OracleFixtureTests.committedCase(name)
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    return try InventoryBuilder(timeZone: zone).scan(paths: [input.path])
  }

  @Test(
    "the cal_master scripts are the recorded ones, in order, byte for byte",
    .scratchDirectory, arguments: ["golden-single-night", "golden-two-night"])
  func testMasterBuilder_scriptsMatchRecorded(name: String) async throws {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try Self.scan(name, under: root)
    let masters = root.appendingPathComponent("work/run_R/masters")
    let siril = RecordingSiril()
    let result = try await MasterBuilder(runner: siril.runner).build(
      inventory, into: masters, work: root.appendingPathComponent("work/run_R"))

    let recorded = try OracleFixtureTests.committedCase(name).scripts().filter { $0.name.contains("_cal_master_") }
    let ours = siril.calls.map {
      $0.script.replacingOccurrences(of: masters.path, with: "<ROOT>/work/run_<RUN>/masters")
    }
    #expect(ours == recorded.map(\.text))
    #expect(result.warnings.isEmpty)
    #expect(siril.calls.allSatisfy { $0.directory.lastPathComponent.hasPrefix("cal_master_") })
  }

  static func darkSet(frames: Int, in dir: URL) throws -> FrameSet {
    let paths = try (0..<frames).map { index -> String in
      let url = dir.appendingPathComponent("raw/dark_\(index).fits")
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("dark \(index)".utf8).write(to: url)
      return url.path
    }
    return CalibrationFixtures.set(
      CalibrationFixtures.calibrationKey(.dark, exposureMs: 60000, gain: 100, offset: 10, tempC: -10), paths: paths)
  }

  static func inventory(_ sets: [FrameSet]) -> Inventory {
    var inventory = Inventory(root: "", frames: [])
    inventory.sets = sets
    return inventory
  }

  @Test("into the library a master appears only complete, with its .sig; a failure leaves nothing", .scratchDirectory)
  func testAtomicWrite() async throws {
    let root = try ScratchDirectory.url
    let library = root.appendingPathComponent("library")
    let final = library.appendingPathComponent("master_DARK_60000ms_g100o10_b1_-10C.fits").path
    let set = try Self.darkSet(frames: 3, in: root)
    let watcher = RecordingSiril(onRun: { _ in
      #expect(!FileManager.default.fileExists(atPath: final), "the final name exists while Siril writes")
    })
    let built = try await MasterBuilder(runner: watcher.runner).build(
      Self.inventory([set]), into: library, work: root.appendingPathComponent("work"), publish: .atomic(runID: "run_1"))
    #expect(built.masters.map(\.path) == [final])
    #expect(FileManager.default.fileExists(atPath: final))
    #expect(PoolSignature.proves(master: final, builtFrom: set.frames.map(\.path)))
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.path).allSatisfy { !$0.hasPrefix(".tmp_") })
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("work/cal_master_DARK_60000ms_g100o10_b1_-10C").path))

    let failing = root.appendingPathComponent("failing")
    let broken = RecordingSiril(fail: { _ in true })
    let failed = try await MasterBuilder(runner: broken.runner).build(
      Self.inventory([set]), into: failing, work: root.appendingPathComponent("work2"), publish: .atomic(runID: "run_2"))
    #expect(failed.masters.isEmpty)
    #expect(failed.warnings.first?.hasPrefix("stack master master_DARK_60000ms_g100o10_b1_-10C:") == true)
    #expect(try FileManager.default.contentsOfDirectory(atPath: failing.path).isEmpty)
  }

  @Test("a direct build that fails removes its partial master", .scratchDirectory)
  func testMasterBuilder_directFailure() async throws {
    let root = try ScratchDirectory.url
    let set = try Self.darkSet(frames: 3, in: root)
    let result = try await MasterBuilder(runner: RecordingSiril(fail: { _ in true }).runner).build(
      Self.inventory([set]), into: root.appendingPathComponent("masters"), work: root.appendingPathComponent("work"))
    #expect(result.masters.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("masters").path).isEmpty)
  }

  @Test("a library master proven by its .sig is reused; another pool's master is rebuilt", .scratchDirectory)
  func testMasterBuilder_reuse() async throws {
    let root = try ScratchDirectory.url
    let library = root.appendingPathComponent("library")
    let set = try Self.darkSet(frames: 3, in: root)
    _ = try await MasterBuilder(runner: RecordingSiril().runner).build(
      Self.inventory([set]), into: library, work: root.appendingPathComponent("w1"), publish: .atomic(runID: "a"))
    let indexed = try CalibrationLibrary(folder: library).scan().compactMap { row -> CalibrationMaster? in
      var master = MasterName.parse(row.path)
      master?.frameCount = row.frameCount
      master?.fromLibrary = true
      return master
    }

    let again = RecordingSiril()
    let reused = try await MasterBuilder(runner: again.runner).build(
      Self.inventory([set]), into: library, work: root.appendingPathComponent("w2"), publish: .atomic(runID: "b"),
      library: indexed)
    #expect(again.calls.isEmpty)
    #expect(reused.masters.first?.fromLibrary == false)
    #expect(reused.warnings == ["reused library master DARK (3 frames — same source frames)"])

    let other = try Self.darkSet(frames: 2, in: root.appendingPathComponent("other"))
    let rebuild = RecordingSiril()
    let rebuilt = try await MasterBuilder(runner: rebuild.runner).build(
      Self.inventory([other]), into: library, work: root.appendingPathComponent("w3"), publish: .atomic(runID: "c"),
      library: indexed)
    #expect(rebuild.calls.count == 1)
    #expect(rebuilt.masters.count == 1)
    #expect(
      rebuilt.warnings.contains(
        "rebuilding the DARK master from this run's 2 frame(s) — the library master (3 frames) was built from different frames"))
    #expect(rebuilt.warnings.contains { $0.contains("2-frame pool") })
  }

  @Test("a lone frame is promoted with fmul 1.0 and a note", .scratchDirectory)
  func testMasterBuilder_loneFrame() async throws {
    let root = try ScratchDirectory.url
    let siril = RecordingSiril()
    let result = try await MasterBuilder(runner: siril.runner).build(
      Self.inventory([try Self.darkSet(frames: 1, in: root)]), into: root.appendingPathComponent("m"),
      work: root.appendingPathComponent("w"))
    let masters = root.appendingPathComponent("m").path
    #expect(
      siril.calls.first?.script
        == "requires 1.2.0\nsetext fits\nset32bits\nconvert cal -out=.\nload cal_00001\nfmul 1.0\n"
        + "save \(masters)/master_DARK_60000ms_g100o10_b1_-10C\n")
    #expect(result.warnings == [MasterNotes.lonePromotion("master_DARK_60000ms_g100o10_b1_-10C", type: .dark)])
  }

  @Test("a flat whose bias calibration fails is stacked without it, and says so", .scratchDirectory)
  func testMasterBuilder_flatRetry() async throws {
    let root = try ScratchDirectory.url
    let flat = CalibrationFixtures.set(
      CalibrationFixtures.calibrationKey(.flat, filter: "L", exposureMs: 5, gain: 100, offset: 10), count: 3)
    let bias = CalibrationFixtures.set(CalibrationFixtures.calibrationKey(.bias, gain: 100, offset: 10), count: 3)
    let siril = RecordingSiril(fail: { $0.contains("-bias=") })
    let result = try await MasterBuilder(runner: siril.runner).build(
      Self.inventory([bias, flat]), into: root.appendingPathComponent("m"), work: root.appendingPathComponent("w"))
    #expect(result.masters.map(\.type) == [.bias, .flat])
    #expect(siril.calls.count == 3)
    #expect(siril.calls.last?.directory.lastPathComponent.hasSuffix("_uncal") == true)
    #expect(result.warnings.contains { $0.hasPrefix("flat master_FLAT_L_5ms_g100o10_b1_0C: stacked WITHOUT its bias") })
  }
}
