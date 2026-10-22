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
    #expect(panel.help(for: "trail_mask_k", locale: french) == definition + "\n" + why.french)
    let english = panel.help(for: "trail_mask_k", locale: Locale(identifier: "en"))
    #expect(english.hasSuffix(why.english))
    #expect(HelpMarkdown.parse(panel.help(for: "trail_mask_k", locale: french)).count == 2)

    // A knob the profile does not set keeps the definition only.
    let other = AppGlossary.term(Knob.termID("fwhm_sigma"), locale: french, in: AppGlossary.knobs)
    #expect(panel.help(for: "fwhm_sigma", locale: french) == other.definition)
  }
}
