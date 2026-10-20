import Foundation
import HelpKit
import TestSupport
import Testing

/// The glossary's own gate, on scratch folders: missing locale, missing term, long definition.
@Suite("Glossary gate — every term in fr and en, one short line each")
struct GlossaryGateTests {
  /// Writes `<root>/<locale>/glossary.json` holding `entries` (id → term JSON).
  static func write(_ entries: [String: String], locale: String, under root: URL) throws {
    let folder = root.appendingPathComponent(locale)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let json = "{" + entries.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ") + "}"
    try Data(json.utf8).write(to: folder.appendingPathComponent("glossary.json"))
  }

  static let term = #"{"label": "Brutes", "definition": "Poses de la cible."}"#

  @Test("the shipped glossary is readable in both locales")
  func testBundled() {
    #expect(Glossary.bundled.term("frame.light", locale: "fr")?.label == "Brutes")
    #expect(Glossary.bundled.term("frame.light", locale: "en")?.label == "Lights")
  }

  @Test("a missing locale, a missing term and an over-long definition fail", .scratchDirectory)
  func testProblems() throws {
    let root = try ScratchDirectory.url
    let long = #"{"label": "Lights", "definition": "\#(String(repeating: "word ", count: 30))"}"#
    try Self.write(["frame.light": Self.term], locale: "fr", under: root)
    try Self.write(["frame.light": long, "frame.old": Self.term], locale: "en", under: root)
    let glossary = Glossary(root: root)
    #expect(
      glossary.problems(ids: ["frame.light", "frame.dark"]) == [
        "frame.dark: no fr term",
        "frame.light (en): definition of 30 words, one line of 1…24",
        "frame.dark: no en term",
      ])
    #expect(glossary.stale(ids: ["frame.light"], locale: "en") == ["frame.old"])
    #expect(Glossary(root: root.appendingPathComponent("none")).problems(ids: []).count == 2)
  }
}
