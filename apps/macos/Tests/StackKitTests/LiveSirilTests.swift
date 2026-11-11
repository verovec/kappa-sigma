import Foundation
import StackKit
import TestSupport
import Testing

/// The verbs the builders emit, against a real `siril-cli -p` (skips without Siril).
@Suite(
  "Live Siril pipe grammar", .liveFixtures,
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .tags(.live), .serialized,
  .timeLimit(.minutes(2)))
struct LiveSirilTests {
  /// Siril's answer to a verb it does not know (French or English locale).
  static func isUnknownVerb(_ log: [String]) -> Bool {
    log.contains {
      let lower = $0.lowercased()
      return lower.contains("commande inconnue") || lower.contains("unknown command")
        || lower.contains("not available in") || lower.contains("n'est pas disponible")
    }
  }

  @Test("every verb the builders emit is accepted in pipe mode", .scratchDirectory)
  func testPipeGrammarAcceptsEveryVerb() async throws {
    let session = SirilSession(
      binary: try SirilTool.locate(), workDirectory: try ScratchDirectory.url)
    try await session.start()
    var rejected: [String] = []
    var silent: [String] = []
    for command in SirilCommand.samples {
      let replies = LineSink()
      var log: [String] = []
      do {
        log = try await session.exec(command, onLine: replies.append)
      } catch let SirilError.commandFailed(_, hint) {
        // Wrong arguments or missing files are fine here: only the verb is under test.
        log = [hint]
      }
      // Proof the real Siril answered: at least `status: starting` and a final status.
      if replies.lines.filter({ $0.status != nil }).count < 2 { silent.append(command) }
      if Self.isUnknownVerb(log) { rejected.append(command) }
    }
    // Negative control: the detection must see a verb Siril does not know.
    do {
      _ = try await session.exec("astrostack_unknown_verb x")
      Issue.record("an unknown verb was accepted")
    } catch let SirilError.commandFailed(_, hint) {
      #expect(Self.isUnknownVerb([hint]), "unknown-verb reply not recognised: \(hint)")
    }
    await session.stop()
    #expect(silent.isEmpty, "no status lines for: \(silent)")
    #expect(rejected.isEmpty, "rejected in pipe mode: \(rejected)")
  }

  @Test(
    "calibrate and stack in folders whose names have a space (card 0112: « M_31 2.astrostack »)",
    .scratchDirectory)
  func testStackIntoPathWithSpace() async throws {
    let work = try ScratchDirectory.url.appendingPathComponent("M_31 2.astrostack/work")
    for index in 1...3 {
      try TestFITS.write(
        String(format: "light_%05d.fit", index), in: work, pixel: UInt16(400 + index), cards: [:])
    }
    let out = work.deletingLastPathComponent().appendingPathComponent("stacks/run 1/master_RGB")
    try FileManager.default.createDirectory(
      at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dark = try TestFITS.write(
      "my darks/dark.fit", in: try ScratchDirectory.url, pixel: 100, cards: [:])
    let session = SirilSession(binary: try SirilTool.locate(), workDirectory: work)
    try await session.start()
    do {
      _ = try await session.exec(SirilCommand.link(seq: "light").line)
      let masters = CalibrationMasters(dark: dark.path)
      _ = try await session.exec(
        SirilCommand.calibrate(seq: "light_", arguments: masters.arguments).line)
      _ = try await session.exec(
        SirilCommand.stack(seq: "pp_light_", clause: "sum", filterIncluded: false, out: out.path)
          .line)
    } catch {
      await session.stop()
      throw error
    }
    await session.stop()
    let written = ["fit", "fits"].map { out.appendingPathExtension($0) }
    #expect(written.contains { FileManager.default.fileExists(atPath: $0.path) })
  }

  @Test(
    "a script with a line longer than the pipe reads runs whole in script mode, on the real Siril",
    .scratchDirectory)
  func testLongLineRunsThroughTheFallback() async throws {
    let scratch = try ScratchDirectory.url
    // A frame so deep that `load <path>` is over 510 bytes: what a deep scratch folder does to
    // a `calibrate` naming its masters.
    var deep = scratch
    while "load \(deep.path)/frame".utf8.count <= SirilSession.maxCommandBytes {
      deep.appendPathComponent(String(repeating: "d", count: 100))
    }
    try TestFITS.write("frame.fits", in: deep, pixel: 1200, cards: [:])
    let sink = LineSink()
    let runner = SirilRunner.make(mode: .pipe, binary: try SirilTool.locate(), work: scratch)
    let script = SirilScript([.load(deep.appendingPathComponent("frame").path), .save("copy")])

    // Cut at 510 bytes, Siril would load nothing and the save would fail the script.
    _ = try await runner.run(script, scratch.appendingPathComponent("lane"), sink.append)

    #expect(
      FileManager.default.fileExists(
        atPath: scratch.appendingPathComponent("lane/copy.fits").path),
      "the long `load` was read whole: its image was saved")
    #expect(sink.lines.first?.text.contains("script mode") == true)
  }
}
