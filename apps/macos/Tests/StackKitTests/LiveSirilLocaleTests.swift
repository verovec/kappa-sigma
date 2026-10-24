import Foundation
import StackKit
import TestSupport
import Testing

/// Siril speaks English to the app on a French Mac (card 0124): the PO's shell and the app both
/// carry `LANG=fr_FR.UTF-8`, which Siril followed until every launch forced its locale.
@Suite(
  "Live Siril locale — English whatever the Mac's language", .liveFixtures,
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .tags(.live), .serialized,
  .timeLimit(.minutes(2)))
struct LiveSirilLocaleTests {
  /// Siril's echo of a command in French, the sentence its log readers would miss.
  static let french = "Exécution de la commande"

  @Test("a script (-s mode: plate solve, SPCC, masters) logs in English", .scratchDirectory)
  func testScriptModeLogsInEnglish() async throws {
    let runner = SirilRunner.live(binary: try SirilTool.locate())
    let log = try await runner.run(SirilScript([]), try ScratchDirectory.url) { _ in }
    #expect(log.contains("Running command: requires"), "\(log)")
    #expect(!log.contains(Self.french))
  }

  @Test("a pipe session (preprocessing runs) logs in English", .scratchDirectory)
  func testPipeModeLogsInEnglish() async throws {
    let session = SirilSession(
      binary: try SirilTool.locate(), workDirectory: try ScratchDirectory.url)
    try await session.start()
    let log: [String]
    do {
      log = try await session.exec("set32bits")
    } catch {
      await session.stop()
      throw error
    }
    await session.stop()
    #expect(log.contains("Running command: set32bits"), "\(log)")
    #expect(!log.contains { $0.contains(Self.french) }, "French reply: \(log)")
  }
}
