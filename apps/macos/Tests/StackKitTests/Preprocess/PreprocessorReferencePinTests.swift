import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// The registration reference breakpoint (card 0096): with `reference_breakpoint` on, every lane
/// pauses once its frames are measured and before the registration is applied; the user's pin
/// becomes the `setref`. No pin, or the elected frame, leaves the recorded scripts byte for byte.
@Suite("Preprocessor — the registration reference pin before the registration is applied")
struct PreprocessorReferencePinTests {
  /// Every `reference` event a run raised, and the finished result.
  struct Replay {
    let siril: PipelineSiril
    let result: PreprocessResult
    let paused: [PreprocessEvent.Reference]
  }

  /// Replays `oracle` with `settings`, answering each reference pause with `pin(lane)`.
  static func replay(
    _ oracle: OracleCase, root: URL, settings: PreprocessSettings,
    edge: EdgeCropper.Measurement = PreprocessTwoNightOracleTests.fullField,
    fails: @escaping @Sendable (String) -> Bool = { _ in false },
    pin: @escaping @Sendable (String) -> Int? = { _ in nil }
  ) async throws -> Replay {
    let inventory = try MasterBuilderTests.scan(oracle.manifest.caseName, under: root)
    let playback = PreprocessOracleTests.Playback(try oracle.grades())
    let siril = PipelineSiril(sequence: { playback.sequences[$0] }, fails: fails)
    let tools = Preprocessor.Tools(
      runner: siril.runner, trailProbe: { frame, _ in playback.trail(frame) },
      edgeMeasure: { _ in edge })
    let request = PreprocessRequest(
      inventory: inventory,
      output: root.appendingPathComponent("out/TESTFIELD/\(PreprocessOracleTests.runID)"),
      work: root.appendingPathComponent("work/run_\(PreprocessOracleTests.runID)"),
      runID: PreprocessOracleTests.runID, settings: settings)
    let paused = Mutex<[PreprocessEvent.Reference]>([])
    let result = try await Preprocessor(tools: tools).perform(request) { event in
      guard case .reference(let reference) = event else { return }
      paused.withLock { $0.append(reference) }
      reference.gate.resume(pin(reference.lane))
    }
    return Replay(siril: siril, result: result, paused: paused.withLock { $0 })
  }

  static var breakpointOn: PreprocessSettings {
    var settings = PreprocessSettings.recorded
    settings.referenceBreakpoint = true
    return settings
  }

  static func setrefs(_ siril: PipelineSiril) -> [String] {
    siril.calls.flatMap { $0.script.split(separator: "\n").filter { $0.hasPrefix("setref") } }
      .map(String.init)
  }

  @Test(
    "two nights: no pin or the elected frame keeps the recorded scripts; off, no event",
    .scratchDirectory, arguments: ["none", "elected", "off"])
  func testReferenceBreakpointByteIdenticalWhenUnpinned(_ mode: String) async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-two-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let replay = try await Self.replay(
      oracle, root: root, settings: mode == "off" ? .recorded : Self.breakpointOn,
      fails: { $0.contains("seqsubsky") }, pin: { _ in nil })
    let recorded = try PreprocessTwoNightOracleTests.expected(oracle)
    let ours = replay.siril.calls.map { PreprocessOracleTests.normalize($0.script, root: root) }
    #expect(ours.count >= recorded.count, "every recorded script was emitted")
    for (index, script) in recorded.enumerated() where index < ours.count {
      #expect(ours[index] == script.text, "script \(script.name)")
    }
    let recordedSetrefs = try oracle.registration().setref.map(\.command)
    #expect(Self.setrefs(replay.siril) == recordedSetrefs)
    if mode == "off" {
      #expect(replay.paused.isEmpty)
    } else {
      // One pause per lane: L and R over two nights, G and B over the anchor night alone.
      #expect(replay.paused.map(\.lane) == ["L", "R", "G", "B"])
      let left = try #require(replay.paused.first)
      #expect(left.elected == 4 && left.candidates.count == 5 && left.nights.count == 5)
      #expect(left.nights[0] == "2020-05-15" && left.nights[4] == "2024-03-01")
      #expect(left.candidates.allSatisfy { $0.fwhm > 0 && !$0.rejected }, "measured, not graded")
      #expect(left.parity.count == 5)
      #expect(replay.result.channels.allSatisfy { $0.referencePin == nil })
    }
    if mode == "elected" {
      // Pinned on the elected frame: the same scripts, and the pin recorded.
      let pinned = try await Self.replay(
        oracle, root: root, settings: Self.breakpointOn, fails: { $0.contains("seqsubsky") },
        pin: { lane in ["L": 4, "R": 4, "G": 2, "B": 2][lane] })
      let theirs = pinned.siril.calls.map { PreprocessOracleTests.normalize($0.script, root: root) }
      #expect(theirs == ours)
      #expect(pinned.result.channels.map(\.referencePin) == [4, 4, 2, 2])
    }
  }

  @Test(
    "two nights, pin ≠ elected on L: one setref changes, the selection holds, the canvas follows",
    .scratchDirectory)
  func testPinnedReferenceEmitsOneSetref() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-two-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let replay = try await Self.replay(
      oracle, root: root, settings: Self.breakpointOn, fails: { $0.contains("seqsubsky") },
      pin: { lane in lane == "L" ? 1 : nil })
    let recorded = try oracle.registration().setref.map(\.command)
    let ours = Self.setrefs(replay.siril)
    #expect(ours.count == recorded.count)
    #expect(
      ours.first == "setref light 1" && Array(ours.dropFirst()) == Array(recorded.dropFirst()))
    let left = try #require(replay.result.channels.first)
    #expect(left.referencePin == 1 && left.reference == 1)
    #expect(left.grades.allSatisfy { !$0.rejected }, "the selection is the recorded one")
    #expect(
      left.frameHomographies[0] == [1, 0, 0, 0, 1, 0, 0, 0, 1], "the pinned frame is the canvas")
    #expect(left.nights.map(\.session) == ["2020-05-15", "2024-03-01"])
    let selection = try oracle.selection()
    #expect(left.kept.count == selection.channels[0].kept.filter { !$0.isEmpty }.count)
  }

  @Test("a context stays parallel when the sequence has more lines than frames")
  func testContextStaysParallel() {
    let sequence = SirilSequence(
      parsing: Array(repeating: PipelineSiril.healthyLine, count: 3).joined(separator: "\n"))
    var frame = CaptureFrame(path: "/c/1.fits")
    frame.session = "2026-09-22"
    let context = ReferencePinContext(
      lane: "L", sequence: sequence, frames: [frame], parity: [.mirrored], elected: 2)
    #expect(context.candidates.map(\.index) == [1, 2, 3])
    #expect(context.nights == ["2026-09-22", "", ""])
    #expect(context.parity == [.mirrored, .unprobed, .unprobed])
    #expect(context.accepts(3) && !context.accepts(4) && !context.accepts(0))

    // A frame measured without a transform (stars found, no H line) is no candidate for a pin:
    // the engine's rule, the same the review applies.
    let measured = SirilSequence(
      parsing: [PipelineSiril.healthyLine, "R0 3 3 0.95 0 0.01 30"].joined(separator: "\n"))
    let partial = ReferencePinContext(
      lane: "L", sequence: measured, frames: [], parity: [], elected: 1)
    #expect(partial.registered == [true, false] && partial.candidates[1].fwhm == 3)
    #expect(partial.accepts(1) && !partial.accepts(2))
  }

  @Test("the election falls back to Siril's own reference when no anchor-night frame registered")
  func testElectionFallsBackToSirilsReference() {
    let dropped = "R0 0 0 0 0 0 0"
    let text = [
      "S 'light_' 1 4 4 0 0 0 1", PipelineSiril.healthyLine, PipelineSiril.healthyLine,
      dropped, dropped,
    ].joined(separator: "\n")
    let sequence = SirilSequence(parsing: text)
    #expect(RegistrationReview.election(sequence, spans: [0..<2, 2..<4], anchor: 0) == 2)
    #expect(RegistrationReview.election(sequence, spans: [0..<2, 2..<4], anchor: 1) == 1)
    let unset = SirilSequence(parsing: [dropped, dropped].joined(separator: "\n"))
    #expect(RegistrationReview.election(unset, spans: [0..<2], anchor: 0) == nil)
  }

  @Test(
    "two nights, a pin the review refuses: a warning, the election stands, no pin recorded",
    .scratchDirectory)
  func testRefusedPinKeepsTheElection() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-two-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let replay = try await Self.replay(
      oracle, root: root, settings: Self.breakpointOn, fails: { $0.contains("seqsubsky") },
      pin: { lane in lane == "L" ? 99 : nil })
    let recorded = try oracle.registration().setref.map(\.command)
    #expect(Self.setrefs(replay.siril) == recorded, "the election stands")
    let left = try #require(replay.result.channels.first)
    #expect(left.referencePin == nil && left.reference == 4, "values shown = values applied")
    #expect(left.warnings.contains { $0.contains("pinned reference frame 99 did not register") })
  }

  @Test(
    "one night, two-pass: a pin on the election keeps the scripts and notes the election",
    .scratchDirectory)
  func testTwoPassPinOnElectionIsByteIdentical() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-single-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    var twoPass = Self.breakpointOn
    twoPass.register2Pass = true
    let unpinned = try await Self.replay(
      oracle, root: root, settings: twoPass, edge: PreprocessOracleTests.cappedEdge,
      pin: { _ in nil })
    let elected = try #require(unpinned.paused.first?.elected)
    let pinned = try await Self.replay(
      oracle, root: root, settings: twoPass, edge: PreprocessOracleTests.cappedEdge,
      pin: { lane in lane == "L" ? elected : nil })
    #expect(pinned.siril.calls.map(\.script) == unpinned.siril.calls.map(\.script))
    #expect(pinned.result.channels.first?.referencePin == elected)
    #expect(
      pinned.result.channels.first?.selection.notes
        == unpinned.result.channels.first?.selection.notes)
    let moved = try await Self.replay(
      oracle, root: root, settings: twoPass, edge: PreprocessOracleTests.cappedEdge,
      pin: { lane in lane == "L" ? 2 : nil })
    #expect(moved.siril.calls.contains { $0.script.contains("setref pp_light 2\nseqapplyreg") })
    #expect(
      moved.result.channels.first?.selection.notes.contains {
        $0.hasPrefix("L: reference pinned on frame 2/")
      } == true, "the note names the pin, not the election")
  }

  @Test(
    "one night: pin ≠ Siril’s → setref + one re-registration; pin = Siril’s → unchanged",
    .scratchDirectory)
  func testSingleNightPinReRegisters() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-single-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let recorded = try oracle.scripts().filter { $0.number <= 18 }.map(\.text)
    let same = try await Self.replay(
      oracle, root: root, settings: Self.breakpointOn, edge: PreprocessOracleTests.cappedEdge,
      pin: { lane in lane == "L" ? 1 : nil })
    let ours = same.siril.calls.map { PreprocessOracleTests.normalize($0.script, root: root) }
    #expect(Array(ours.prefix(recorded.count)) == recorded)
    #expect(same.paused.map(\.lane) == ["L", "R", "G", "B"])
    #expect(same.paused.first?.elected == 1, "Siril's own reference: frame 1 (no S line → 1)")

    let moved = try await Self.replay(
      oracle, root: root, settings: Self.breakpointOn, edge: PreprocessOracleTests.cappedEdge,
      pin: { lane in lane == "L" ? 3 : nil })
    let scripts = moved.siril.calls.filter { $0.directory.lastPathComponent == "light_L" }
      .map(\.script)
    let registrations = scripts.filter { $0.contains("register pp_light\n") }
    #expect(registrations.count == 2, "registered once, then once more onto the pin")
    #expect(scripts.contains { $0.contains("setref pp_light 3\nregister pp_light\n") })
    let left = try #require(moved.result.channels.first)
    #expect(left.referencePin == 3 && left.reference == 3)
    #expect(moved.result.channels.dropFirst().map(\.referencePin) == [nil, nil, nil])
  }
}
