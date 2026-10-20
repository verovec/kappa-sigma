import Foundation
import StackKit
import TestSupport
import Testing

/// The run against the legacy recording of 0044 case (b), two nights (L/R on both, G/B on the
/// anchor night): Siril replayed from `grades.json`, the per-frame flatten failing as it did.
///
/// One documented difference (PO decision 2026-10-20): the legacy engine re-linked the merge
/// folder after the failed flatten without cleaning it, so L and R stacked every frame twice
/// (`select r_light_ 1 10`, a 10-frame clause). The port cleans the folder: L and R stack their 5
/// real frames, so scripts 0013 and 0019 select 1…5 with the 5-frame clause. Nothing else moves.
@Suite("Preprocess oracle — the synthetic two nights against the legacy recording")
struct PreprocessTwoNightOracleTests {
  static let fullField = EdgeCropper.Measurement(
    rect: EdgeRect(x0: 0, y0: 0, x1: 256, y1: 256), capped: false, width: 256, height: 256)

  /// The recorded scripts this card emits (up to the neutralized composite), with the fix applied.
  static func expected(_ oracle: OracleCase) throws -> [OracleScript] {
    try oracle.scripts().filter { $0.number <= 34 }.map { script in
      guard script.text.contains("select r_light_ 1 10\n") else { return script }
      let fixed = script.text.replacingOccurrences(
        of: "select r_light_ 1 10\n", with: "select r_light_ 1 5\n"
      )
      .replacingOccurrences(of: "rej winsorized 3 3", with: "rej percentile 0.2 0.1")
      return try #require(OracleScript(name: script.name, text: fixed))
    }
  }

  @Test(
    """
    scripts byte-equal in order (the duplicate-frame fix aside); selection, nights and \
    references as recorded
    """,
    .scratchDirectory)
  func testTwoNightScriptsAndSelection() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-two-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let (siril, result) = try await PreprocessOracleTests.run(
      root: root, oracle: oracle, edge: Self.fullField, fails: { $0.contains("seqsubsky") })

    let recorded = try Self.expected(oracle)
    let ours = siril.calls.map {
      (
        PreprocessOracleTests.normalize($0.directory.lastPathComponent, root: root),
        PreprocessOracleTests.normalize($0.script, root: root)
      )
    }
    #expect(ours.map(\.0) == recorded.map(\.directory))
    for (index, script) in recorded.enumerated() where index < ours.count {
      #expect(ours[index].1 == script.text, "script \(script.name)")
    }

    let selection = try oracle.selection()
    #expect(result.channels.map(\.filter) == selection.channels.map(\.filter))
    for (channel, recordedChannel) in zip(result.channels, selection.channels) {
      let kept = channel.kept.map { PreprocessOracleTests.normalize($0, root: root) }
      #expect(kept == recordedChannel.kept.filter { !$0.isEmpty }, "\(channel.filter) kept")
      #expect(channel.inputFrames == recordedChannel.inputFrames)
      let nights = (recordedChannel.groups ?? []).map {
        "\($0.session ?? "") \($0.stackedFrames)/\($0.rejectedFrames)"
      }
      #expect(channel.nights.map { "\($0.session) \($0.stacked)/\($0.rejected)" } == nights)
    }
    let registration = try oracle.registration()
    let setrefs = siril.calls.flatMap {
      $0.script.split(separator: "\n").filter { $0.hasPrefix("setref") }
    }
    #expect(setrefs.map(String.init) == registration.setref.map(\.command))
    #expect(
      registration.channels.allSatisfy { $0.preRejected.isEmpty }
        && result.channels.allSatisfy { $0.grades.allSatisfy { !$0.rejected } })
  }

  @Test(
    "per-channel notes and run warnings as recorded (finish-only warnings aside)", .scratchDirectory
  )
  func testTwoNightNotesAndWarnings() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-two-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let (_, result) = try await PreprocessOracleTests.run(
      root: root, oracle: oracle, edge: Self.fullField, fails: { $0.contains("seqsubsky") })
    let recorded = (try oracle.run().warnings ?? []).filter { !$0.hasPrefix("finish quality") }
    #expect(result.warnings == recorded)
  }
}
