import Foundation
import StackKit
import TestSupport
import Testing

/// `ChannelStacker` is `processChannel` + `finishStackedChannel` on one night: the golden case's
/// L set, with a Siril double steering what registration reports.
@Suite("ChannelStacker — one light set to its linear master")
struct ChannelStackerTests {
  struct Fixture {
    let root: URL
    let inventory: Inventory
    let masters: [CalibrationMaster]
    var work: URL { root.appendingPathComponent("work/run_R") }
    var out: URL { root.appendingPathComponent("out") }

    var lights: FrameSet {
      get throws { try inventory.sets.first { $0.key.type == .light && $0.key.filter == "L" }.unwrapped("L") }
    }

    static func make() async throws -> Self {
      let root = try InventoryBuilderFallbackTests.folder("scan")
      let inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
      let work = root.appendingPathComponent("work/run_R")
      let built = try await MasterBuilder(runner: PipelineSiril().runner).build(
        inventory, into: work.appendingPathComponent("masters"), work: work)
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent("out"), withIntermediateDirectories: true)
      return Self(root: root, inventory: inventory, masters: built.masters)
    }

    func stack(_ siril: PipelineSiril, set: FrameSet? = nil) async throws -> ChannelOutcome {
      try await ChannelStacker(runner: siril.runner, trailProbe: { _, _ in (false, 0.1) }).stack(
        set ?? lights, filter: "L", inventory: inventory, masters: masters, work: work, out: out)
    }
  }

  static let dropped = "R0 0 0 0 0 0 0"

  @Test("an unregistered frame is graded out of the stack; the master loses its BAYERPAT", .scratchDirectory)
  func testStack_unregisteredFrame() async throws {
    let fixture = try await Fixture.make()
    let siril = PipelineSiril { _ in [PipelineSiril.healthyLine, Self.dropped, PipelineSiril.healthyLine].joined(separator: "\n") }
    let outcome = try await fixture.stack(siril)
    #expect(outcome.error == nil)
    #expect(outcome.stackedFrames == 2 && outcome.kept.count == 2)
    #expect(outcome.warnings == ["L: only 2/3 frames registered — 1 dropped (no stars matched)"])
    #expect(siril.calls.last?.script.contains("select r_pp_light_ 1 2\n") == true)
    let master = try #require(outcome.masterPath)
    let header = try String(bytes: Data(contentsOf: URL(fileURLWithPath: master)).prefix(2880), encoding: .ascii)
    #expect(header?.contains("BAYERPAT") == false)
    #expect(!FileManager.default.fileExists(atPath: fixture.work.appendingPathComponent("light_L").path))
  }

  @Test("one registered frame is the master; none is a channel error", .scratchDirectory)
  func testStack_oneOrNoneRegistered() async throws {
    let fixture = try await Fixture.make()
    let one = try await fixture.stack(PipelineSiril { _ in [PipelineSiril.healthyLine, Self.dropped, Self.dropped].joined(separator: "\n") })
    #expect(one.error == nil && one.stackedFrames == 1)
    #expect(one.warnings.last == "L: only 1 frame registered — using it as the channel master (no stacking)")
    #expect(FileManager.default.fileExists(atPath: try #require(one.masterPath)))
    let none = try await fixture.stack(PipelineSiril { _ in [Self.dropped, Self.dropped, Self.dropped].joined(separator: "\n") })
    #expect(none.error == "no frames could be registered" && none.masterPath == nil)
  }

  @Test("a one-frame set is calibrated alone and promoted", .scratchDirectory)
  func testStack_loneFrame() async throws {
    let fixture = try await Fixture.make()
    let full = try fixture.lights
    let lone = FrameSet(key: full.key, frames: [full.frames[0]], indices: [full.indices[0]])
    let siril = PipelineSiril()
    let outcome = try await fixture.stack(siril, set: lone)
    #expect(outcome.error == nil && outcome.stackedFrames == 1)
    #expect(siril.calls.map(\.script).last?.contains("calibrate_single light_00001 -dark=") == true)
    #expect(FileManager.default.fileExists(atPath: try #require(outcome.masterPath)))
  }

  @Test("a Siril failure fails the channel, not the run; cancellation ends the run", .scratchDirectory)
  func testStack_failureAndCancel() async throws {
    let fixture = try await Fixture.make()
    let failing = SirilRunner { _, _, _ in throw SirilError.scriptFailed(exitCode: 1, hint: "no stars") }
    let outcome = try await ChannelStacker(runner: failing).stack(
      try fixture.lights, filter: "L", inventory: fixture.inventory, masters: fixture.masters,
      work: fixture.work, out: fixture.out)
    #expect(outcome.error != nil && outcome.masterPath == nil)
    let cancelled = SirilRunner { _, _, _ in throw CancellationError() }
    await #expect(throws: CancellationError.self) {
      _ = try await ChannelStacker(runner: cancelled).stack(
        try fixture.lights, filter: "L", inventory: fixture.inventory, masters: fixture.masters,
        work: fixture.work, out: fixture.out)
    }
  }

  @Test("tags keep letters, digits, - and _; spaces become _; an empty filter is mono")
  func testChannelTag() {
    #expect(ChannelTag.sanitize("H alpha/7é") == "H_alpha7")
    #expect(ChannelTag.sanitize("//") == "session")
    #expect(ChannelTag.of("") == "mono" && ChannelTag.of("OIII") == "OIII")
  }
}
