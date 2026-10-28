import AstroStackApp
import Foundation
import HelpKit
import Testing

/// Settings › Storage has a short card in French and English (card 0114).
@MainActor
@Suite("Setting help — a card per Settings section with one, fr and en")
struct SettingHelpTests {
  @Test("every setting card exists in fr and en, short, its first line the summary")
  func testEverySettingHasCardFrEn() throws {
    #expect(AppGlossary.help.coverageProblems(settings: SettingHelp.ids) == [])
    for id in SettingHelp.ids {
      for language in ["fr", "en"] {
        let locale = Locale(identifier: language)
        let card = try #require(SettingHelp.card(id, locale: locale), "\(id) \(language)")
        #expect(HelpMarkdown.parse(card).count >= 2)
        #expect(SettingHelp.help(id, locale: locale)?.key == .help("setting." + id))
      }
    }
    #expect(SettingHelp.card("storage", locale: Locale(identifier: "fr"))?.contains("Go") == true)
    #expect(
      SettingHelp.card("astro-folder", locale: Locale(identifier: "fr"))?.contains("captures")
        == true)
    #expect(AppGlossary.help.coverageProblems(settings: ["nope"]).count == 2)
  }
}
