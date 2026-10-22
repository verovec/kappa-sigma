import AstroStackApp
import Foundation
import HelpKit
import ProcessKit
import StackKit
import Testing

extension KnobPanelViewModelTests {
  /// Card 0086: a knob's help is its glossary definition and, when the stack's source kept a
  /// profile that sets the knob, that profile's « why » as a second paragraph.
  @Test("testKnobHelpCarriesProfileWhy")
  func testKnobHelpCarriesProfileWhy() throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    let french = Locale(identifier: "fr")
    let definition = AppGlossary.term(
      Knob.termID("trail_mask_k"), locale: french, in: AppGlossary.knobs
    ).definition
    #expect(!definition.isEmpty && panel.help(for: "trail_mask_k", locale: french) == definition)

    let profiles = try ProfileLibrary.builtins(registry: ProcessRegistry.standard())
    let profile = try #require(profiles.first { $0.preprocessing.why["trail_mask_k"] != nil })
    let why = try #require(profile.preprocessing.why["trail_mask_k"])
    panel.profile = profile
    // The why belongs to the profile's value, named with it: « <profile>, <value>: <why> ».
    let value = try #require(profile.preprocessing.knobs["trail_mask_k"])
    let words = KnobPanelViewModel.words(for: value, id: "trail_mask_k", locale: french)
    let line = KnobPanelViewModel.profileLine(
      profile.title.french, words, why.french, locale: french)
    #expect(line.hasSuffix(" : " + why.french), "French spaces its colon: \(line)")
    #expect(panel.help(for: "trail_mask_k", locale: french) == definition + "\n" + line)
    let english = panel.help(for: "trail_mask_k", locale: Locale(identifier: "en"))
    #expect(english.hasSuffix(why.english) && english.contains(profile.title.english))
    #expect(HelpMarkdown.parse(panel.help(for: "trail_mask_k", locale: french)).count == 2)

    // A knob the profile does not set keeps the definition only.
    let other = AppGlossary.term(Knob.termID("fwhm_sigma"), locale: french, in: AppGlossary.knobs)
    #expect(panel.help(for: "fwhm_sigma", locale: french) == other.definition)
  }

  @Test(
    "a profile's value is worded as the panel shows it",
    arguments: [
      (ParamValue.number(3.5), "3,5"), (.flag(true), "Activé"), (.flag(false), "Désactivé"),
      (.choice("sigma"), "Écrêtage sigma"),
    ])
  func testProfileValueWords(value: ParamValue, expected: String) {
    let words = KnobPanelViewModel.words(
      for: value, id: "stack_reject", locale: Locale(identifier: "fr"))
    #expect(words == expected)
    let french = Locale(identifier: "fr")
    #expect(KnobPanelViewModel.words(for: .points([]), id: "stack_reject", locale: french) == nil)
  }
}
