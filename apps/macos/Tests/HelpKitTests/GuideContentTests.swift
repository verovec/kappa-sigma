import Foundation
import HelpKit
import TestSupport
import Testing

/// The first-stack guide's text (card 0061): one short step per line, the same count in every
/// locale.
@Suite("First-stack guide text — seven short steps in fr and en")
struct GuideContentTests {
  @Test("the shipped guide has its seven steps in both locales, each opening on a bold title")
  func testShipped() {
    #expect(HelpIndex.bundled.guideProblems(steps: 7).isEmpty)
    for locale in HelpIndex.locales {
      let steps = HelpIndex.bundled.guide(locale: locale)
      #expect(steps.count == 7)
      for step in steps {
        #expect(HelpMarkdown.parse(step).first?.runs.first?.bold == true, "\(locale): \(step)")
      }
    }
  }

  @Test("a missing locale, a wrong count and an over-long step fail", .scratchDirectory)
  func testProblems() throws {
    let root = try ScratchDirectory.url
    let folder = root.appendingPathComponent("fr/guide")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let long = String(repeating: "mot ", count: 41)
    try Data("**Un.** a\n\n**Deux.** \(long)\n".utf8)
      .write(to: folder.appendingPathComponent("first-stack.md"))
    #expect(
      HelpIndex(root: root).guideProblems(steps: 3) == [
        "guide (fr): 2 steps, not 3", "guide (fr) step 2: 42 words > 40", "guide: no en text",
      ])
  }
}
