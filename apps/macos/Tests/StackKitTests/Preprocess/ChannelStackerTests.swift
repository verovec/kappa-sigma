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
      get throws {
        try inventory.sets.first { $0.key.type == .light && $0.key.filter == "L" }.unwrapped("L")
      }
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

  @Test(
    "two-pass registration notes the elected reference, then applies on its field",
    .scratchDirectory)
  func testStack_twoPass() async throws {
    let fixture = try await Fixture.make()
    let lines = [PipelineSiril.healthyLine, PipelineSiril.healthyLine, PipelineSiril.healthyLine]
    let siril = PipelineSiril { _ in
      (["S 'pp_light_' 1 3 3 0 2 0 1"] + lines).joined(separator: "\n")
    }
    let settings = PreprocessSettings(register2Pass: true)
    let outcome = try await ChannelStacker(runner: siril.runner, settings: settings) { _, _ in nil }
      .stack(
        try fixture.lights, filter: "L", inventory: fixture.inventory, masters: fixture.masters,
        work: fixture.work, out: fixture.out)
    #expect(
      outcome.selection.notes.last?.hasPrefix("L: two-pass registration elected frame 3/3") == true)
    let scripts = siril.calls.map(\.script)
    #expect(scripts.contains { $0.contains("register pp_light -2pass\n") })
    #expect(scripts.contains { $0.contains("seqapplyreg pp_light -framing=current\n") })
  }

  @Test(
    "frames restored for the stack minimum are a warning naming why they were rejected",
    .scratchDirectory)
  func testStack_restoredWarning() async throws {
    let fixture = try await Fixture.make()
    let siril = PipelineSiril()
    let outcome = try await ChannelStacker(runner: siril.runner) { _, _ in (true, 0.9) }.stack(
      try fixture.lights, filter: "L", inventory: fixture.inventory, masters: fixture.masters,
      work: fixture.work, out: fixture.out)
    #expect(outcome.stackedFrames == 2)
    #expect(
      outcome.warnings.last?.hasPrefix("L: stacking 2 survivor(s) — 2 kept despite: trail detected")
        == true)
  }

  @Test(
    "an unregistered frame is graded out of the stack; the master loses its BAYERPAT",
    .scratchDirectory)
  func testStack_unregisteredFrame() async throws {
    let fixture = try await Fixture.make()
    let siril = PipelineSiril { _ in
      [PipelineSiril.healthyLine, Self.dropped, PipelineSiril.healthyLine].joined(separator: "\n")
    }
    let outcome = try await fixture.stack(siril)
    #expect(outcome.error == nil)
    #expect(outcome.stackedFrames == 2 && outcome.kept.count == 2)
    #expect(outcome.warnings == ["L: only 2/3 frames registered — 1 dropped (no stars matched)"])
    #expect(siril.calls.last?.script.contains("select r_pp_light_ 1 2\n") == true)
    let master = try #require(outcome.masterPath)
    let header = try String(
      bytes: Data(contentsOf: URL(fileURLWithPath: master)).prefix(2880), encoding: .ascii)
    #expect(header?.contains("BAYERPAT") == false)
    #expect(
      !FileManager.default.fileExists(atPath: fixture.work.appendingPathComponent("light_L").path))
  }

  @Test("one registered frame is the master; none is a channel error", .scratchDirectory)
  func testStack_oneOrNoneRegistered() async throws {
    let fixture = try await Fixture.make()
    let one = try await fixture.stack(
      PipelineSiril { _ in
        [PipelineSiril.healthyLine, Self.dropped, Self.dropped].joined(separator: "\n")
      })
    #expect(one.error == nil && one.stackedFrames == 1)
    #expect(
      one.warnings.last
        == "L: only 1 frame registered — using it as the channel master (no stacking)")
    #expect(FileManager.default.fileExists(atPath: try #require(one.masterPath)))
    let none = try await fixture.stack(
      PipelineSiril { _ in [Self.dropped, Self.dropped, Self.dropped].joined(separator: "\n") })
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

  @Test(
    "a Siril failure fails the channel, not the run; cancellation ends the run", .scratchDirectory)
  func testStack_failureAndCancel() async throws {
    let fixture = try await Fixture.make()
    let failing = SirilRunner { _, _, _ in
      throw SirilError.scriptFailed(exitCode: 1, hint: "no stars")
    }
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

  @Test(
    "the pixel trail probe reads the frame downsampled; an unreadable frame has no verdict",
    .scratchDirectory)
  func testPixelTrail() throws {
    let folder = try ScratchDirectory.url
    // A diagonal streak over a faintly textured sky.
    var streak = [UInt16](repeating: 1000, count: 64 * 64)
    for index in streak.indices { streak[index] += UInt16(index % 7) }
    for diagonal in 0..<64 { streak[diagonal * 64 + diagonal] = 60000 }
    let frame = try TestFITS.write(
      "streak.fits", in: folder, width: 64, height: 64, planes: [streak], cards: [:])
    let verdict = ChannelStacker.pixelTrail(frame, 32)
    #expect(verdict?.detected == true && (verdict?.score ?? 0) > TrailDetector.voteFraction)
    let absent = ChannelStacker.pixelTrail(folder.appendingPathComponent("absent.fits"), 32)
    #expect(absent == nil)
  }

  @Test("tags keep letters, digits, - and _; spaces become _; an empty filter is mono")
  func testChannelTag() {
    #expect(ChannelTag.sanitize("H alpha/7é") == "H_alpha7")
    #expect(ChannelTag.sanitize("//") == "session")
    #expect(ChannelTag.of("") == "mono" && ChannelTag.of("OIII") == "OIII")
  }
}
