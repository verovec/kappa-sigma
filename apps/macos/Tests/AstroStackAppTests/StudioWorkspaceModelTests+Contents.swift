import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

/// What the combined image holds (card 0131): said under « Combined » whichever history is shown,
/// so colour calibration on a BB + DB stack is not taken to see the lines before line injection.
extension StudioWorkspaceModelTests {
  @Test("testCombinedContentsLine", .scratchDirectory)
  func testCombinedContentsLine() throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    let (en, fr) = (Locale(identifier: "en"), Locale(identifier: "fr"))
    let name = { (id: String, locale: Locale) in
      StudioSelection.label(.branch(id), locale: locale)
    }

    // The broadband combination: the lines wait for line injection.
    let broadband = CombinedContents(holds: ["RGB"], missing: ["Ha", "OIII"])
    #expect(workspace.combinedContents == broadband)
    #expect(
      String(localized: broadband.words(locale: en))
        == "Holds \(name("RGB", en)); not yet \(name("Ha", en)) and \(name("OIII", en)) (to add "
        + "with Line injection or Emission screens).")
    let french = String(localized: broadband.words(locale: fr))
    #expect(
      french.hasPrefix(
        "Contient \(name("RGB", fr)) ; pas encore \(name("Ha", fr)) et \(name("OIII", fr))"))
    #expect(
      french.contains(String(localized: ProcessKitResources.title("Line injection", locale: fr))))

    // Hα injected: OIII still out; the line stays on a branch.
    var injection = ParamSet(schema: LineInjectionProcess.schema)
    try injection.set("haGain", .number(1))
    try workspace.studio.apply(LineInjectionProcess.id, params: injection)
    workspace.select(.branch("Ha"))
    #expect(
      workspace.combinedContents == CombinedContents(holds: ["RGB", "Ha"], missing: ["OIII"]))

    // A palette without the broadband: no process to name.
    var hoo = ParamSet(schema: ChannelCombinationProcess.schema)
    for (slot, source) in [("rSource", "Ha"), ("gSource", "OIII"), ("bSource", "OIII")] {
      try hoo.set(slot, .choice(source))
    }
    try workspace.studio.apply(ChannelCombinationProcess.id, params: hoo)
    let palette = try #require(workspace.combinedContents)
    #expect(palette == CombinedContents(holds: ["Ha", "OIII"], missing: ["RGB"]))
    #expect(
      String(localized: palette.words(locale: en))
        == "Holds \(name("Ha", en)) + \(name("OIII", en)); not \(name("RGB", en)).")
    #expect(
      String(localized: CombinedContents(holds: ["RGB"], missing: []).words(locale: fr))
        == "Contient \(name("RGB", fr)).")
  }

  @Test("testCombinedContentsNamesNoLineProcessWithoutBroadband")
  func testCombinedContentsNamesNoLineProcessWithoutBroadband() {
    // Line injection refuses a base that is not RGB: a combination is what adds OIII there.
    let narrowband = CombinedContents(holds: ["Ha"], missing: ["OIII"])
    let en = Locale(identifier: "en")
    #expect(
      String(localized: narrowband.words(locale: en))
        == "Holds \(StudioSelection.label(.branch("Ha"), locale: en)); not "
        + "\(StudioSelection.label(.branch("OIII"), locale: en)).")
  }

  @Test("testCombinedContentsNoneForASingleLayer", .scratchDirectory)
  func testCombinedContentsNoneForASingleLayer() throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    #expect(workspace.combinedContents == nil)
  }
}
