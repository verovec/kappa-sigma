import Foundation
import HelpKit
import TestSupport
import Testing

/// The stage cards' gate (card 0086), on a scratch root: a missing locale names the stage, a
/// long card is refused, a card reads back.
@Suite("Stage card gate — every stage in fr and en, at most 5 lines")
struct StageCardGateTests {
  static func write(_ text: String, stage: String, locale: String, under root: URL) throws {
    let folder = root.appendingPathComponent(locale).appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: folder.appendingPathComponent(stage + ".md"))
  }

  @Test("a missing locale and a six-line card fail with the stage id", .scratchDirectory)
  func testStageCardGate() throws {
    let root = try ScratchDirectory.url
    try Self.write(
      "What the stage is for.\nWhat you do.\n", stage: "review", locale: "en", under: root)
    try Self.write(
      String(repeating: "Une ligne.\n", count: 6), stage: "export", locale: "fr", under: root)
    try Self.write("One line.\n", stage: "export", locale: "en", under: root)
    let help = HelpIndex(root: root)
    #expect(help.stageCard("review", locale: "en") == "What the stage is for.\nWhat you do.\n")
    #expect(help.stageCard("review", locale: "fr") == nil)
    #expect(
      help.coverageProblems(stages: ["review", "export"]) == [
        "review: no fr stage card", "export (fr): 6 lines > 5",
      ])
  }
}
