import AstroStackApp
import Foundation
import HelpKit
import StackKit
import Testing

/// The Stacking panel's knobs: rendered from `KnobSchema`, simple ones first and the rest behind
/// the disclosure, a changed value badged until reset, the edits written as the patch a run sends.
@MainActor
@Suite("KnobPanelViewModel — simple/advanced split, diff badge, reset, patch")
struct KnobPanelViewModelTests {
  @Test("simple knobs show by default, advanced ones behind the disclosure; nothing is hidden")
  func testSimpleAdvancedSplit() {
    let panel = KnobPanelViewModel(mode: .deepsky)
    #expect(!panel.showsAdvanced, "the advanced knobs start behind the disclosure")
    #expect(panel.simpleRows.map(\.id) == KnobSchema.knobs.filter { $0.level == .simple }.map(\.id))
    #expect(
      Set(panel.simpleRows.map(\.id) + panel.advancedRows.map(\.id))
        == Set(KnobSchema.knobs.map(\.id)),
      "every knob, R2")
    #expect(panel.rows.allSatisfy { $0.isDefault })
  }

  struct Change: Sendable, CustomTestStringConvertible {
    let id: String
    let value: KnobValue
    var testDescription: String { "\(id) = \(value)" }
  }

  @Test(
    "a changed knob is badged and in the patch; reset clears both",
    arguments: [
      Change(id: "fwhm_sigma", value: .number(3.5)),
      Change(id: "stack_reject", value: .choice("sigma")),
      Change(id: "register_2pass", value: .flag(true)), Change(id: "scnr", value: .number(1)),
    ])
  func testDiffBadgeAndReset(_ change: Change) throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set(change.id, to: change.value)
    let row = try #require(panel.rows.first { $0.id == change.id })
    #expect(!row.isDefault && row.value == change.value)
    #expect(panel.patch == KnobPatch(values: [change.id: change.value]))
    #expect(panel.changedCount == 1)

    panel.reset(change.id)
    #expect(panel.rows.first { $0.id == change.id }?.isDefault == true)
    #expect(panel.patch.values.isEmpty)
  }

  @Test("a value back at its default, or refused by the schema, leaves the patch empty")
  func testDefaultOrInvalidValueIsNoEdit() {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("fwhm_sigma", to: .number(9))
    panel.set("register_2pass", to: .number(1))
    panel.set("fwhm_sigma", to: .number(PreprocessSettings.preset(.deepsky).grading.fwhmSigma))
    #expect(panel.patch.values.isEmpty)
  }

  @Test("the nebula preset moves the defaults; an edit it matches is no change there, not lost")
  func testModeChangesDefaults() throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("background_degree", to: .number(2))
    panel.set("fwhm_sigma", to: .number(4))
    panel.mode = .nebula

    #expect(panel.patch == KnobPatch(values: ["fwhm_sigma": .number(4)]))
    let degree = try #require(panel.rows.first { $0.id == "background_degree" })
    #expect(degree.isDefault && degree.value == .number(2))
    let expected = try KnobSchema.apply(panel.patch, to: .preset(.nebula))
    #expect(panel.settings == expected)

    panel.mode = .deepsky
    #expect(
      panel.patch
        == KnobPatch(values: ["background_degree": .number(2), "fwhm_sigma": .number(4)]),
      "switching back keeps the edit the nebula preset matched")
  }

  @Test("a recorded patch the schema refuses is reported, its valid edits kept")
  func testRecordedPatchValidated() {
    let panel = KnobPanelViewModel(
      mode: .deepsky,
      patch: KnobPatch(values: [
        "fwhm_sigma": .number(3.5), "no_such_knob": .flag(true), "stack_feather": .number(9_999),
      ]))
    #expect(panel.ignored == ["no_such_knob", "stack_feather"])
    #expect(panel.patch == KnobPatch(values: ["fwhm_sigma": .number(3.5)]))
    #expect(panel.changedCount == 1)
    panel.resetAll()
    #expect(panel.ignored.isEmpty && panel.patch.values.isEmpty)
  }

  @Test("edits serialise to the exact legacy wire keys a run records")
  func testPatchSerialisation() throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("stack_reject", to: .choice("winsorized"))
    panel.set("stack_reject_low", to: .number(2.5))
    panel.set("stack_weight", to: .choice("none"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(
      String(bytes: try encoder.encode(panel.patch), encoding: .utf8)
        == #"{"stack_reject":"winsorized","stack_reject_low":2.5,"stack_weight":"none"}"#)
  }

  @Test("every knob and every choice has its words in fr and en; no word without a knob")
  func testEveryKnobHasFrEn() {
    let ids = KnobPanelViewModel.termIDs
    #expect(AppGlossary.knobs.problems(ids: ids) == [])
    for locale in HelpIndex.locales {
      #expect(AppGlossary.knobs.stale(ids: ids, locale: locale) == [], "\(locale)")
    }
    #expect(
      AppGlossary.label("knob.fwhm_sigma", locale: Locale(identifier: "fr"), in: AppGlossary.knobs)
        == "Pose floue (σ)")
  }

  @Test("a run of another preset gets the edits measured against that preset")
  func testPatchForAnotherPreset() {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("background_degree", to: .number(1))
    panel.set("fwhm_sigma", to: .number(4))
    #expect(panel.patch == KnobPatch(values: ["fwhm_sigma": .number(4)]))
    #expect(
      panel.patch(for: .nebula)
        == KnobPatch(values: ["background_degree": .number(1), "fwhm_sigma": .number(4)]))
  }
}
