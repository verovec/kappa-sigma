import AstroStackApp
import Foundation
import HelpKit
import StackKit
import Testing

/// The glossary words every case of the catalogs that own the vocabulary, in fr and en.
@Suite("Glossary — one term per frame type, filter, filter set, colour model and stage")
struct GlossaryTests {
  /// Every term id the app asks for, from the catalogs' `allCases`.
  static var ids: [String] {
    FrameType.allCases.map(\.termID) + Filter.allCases.map(\.termID)
      + FilterSet.allCases.map(\.termID) + ColorChoice.allCases.map(\.termID)
      + ColorModel.allCases.map(\.termID) + LinearBundle.Role.allCases.map(\.termID)
      + JourneyStage.allCases.map(\.termID)
  }

  @Test("every frame type, filter, filter set, colour model and stage has a fr and an en term")
  func testEveryFrameTypeFilterAndStageHasFrEn() {
    #expect(AppGlossary.glossary.problems(ids: Self.ids) == [])
    for locale in ["fr", "en"] {
      #expect(AppGlossary.glossary.stale(ids: Self.ids, locale: locale) == [], "\(locale)")
    }
  }

  @Test(
    "the astronomer's words: brutes, offsets, dark-flats in French",
    arguments: zip(
      [FrameType.light.termID, FrameType.bias.termID, FrameType.darkFlat.termID, "stage.review"],
      [("Lights", "Brutes"), ("Bias", "Offsets"), ("Dark flats", "Dark-flats"), ("Review", "Tri")]))
  func testTerms(id: String, labels: (english: String, french: String)) {
    #expect(AppGlossary.label(id, locale: Locale(identifier: "en_FR")) == labels.english)
    #expect(AppGlossary.label(id, locale: Locale(identifier: "fr_CA")) == labels.french)
  }

  @Test("a master's role is worded as its frames; a filter keeps its short name")
  func testRolesAndFilters() {
    #expect(CalibrationRole.allCases.map(\.frameType) == [.dark, .flat, .bias])
    let ha = AppGlossary.term(Filter.hydrogenAlpha.termID, locale: Locale(identifier: "fr"))
    #expect(ha.label == "Hydrogène alpha")
    #expect(!ha.definition.isEmpty)
  }

  @Test("the interface locale is the UI language with the user's region")
  func testInterfaceLocale() {
    let french = AppLocale.interface(preferences: ["fr-FR", "en"], region: .init("FR"))
    #expect(AppLocale.language(of: french) == "fr")
    #expect(french.region == .init("FR"))
    let english = AppLocale.interface(preferences: ["de-DE", "en-US"], region: .init("FR"))
    #expect(AppLocale.language(of: english) == "en", "German falls back to English")
    #expect(english.decimalSeparator == ",", "an English UI keeps the French region's numbers")
    #expect(AppLocale.language(of: Locale(identifier: "de_DE")) == "en")
  }
}
