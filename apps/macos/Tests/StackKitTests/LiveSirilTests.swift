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
}
