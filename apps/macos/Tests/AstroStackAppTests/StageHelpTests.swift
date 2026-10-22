import AstroStackApp
import Foundation
import HelpKit
import ProjectKit
import TestSupport
import Testing

/// `HelpCoverageTests.testEveryStageHasCardFrEn` of card 0086: the six journey stages have a
/// short card in French and English, and the app's `StageHelp` serves the first line as the
/// summary.
@MainActor
@Suite("Stage help — a card per journey stage, fr and en")
struct StageHelpTests {
  @Test("testEveryStageHasCardFrEn")
  func testEveryStageHasCardFrEn() throws {
    let stages = JourneyStage.allCases.map(\.rawValue)
    #expect(stages.count == 6)
    #expect(AppGlossary.help.coverageProblems(stages: stages) == [])
    for stage in JourneyStage.allCases {
      for language in ["fr", "en"] {
        let locale = Locale(identifier: language)
        let card = try #require(StageHelp.card(stage, locale: locale), "\(stage) \(language)")
        #expect(HelpMarkdown.parse(card).count >= 2, "\(stage) \(language): what for, what to do")
        let summary = try #require(StageHelp.summary(stage, locale: locale))
        #expect(card.hasPrefix(summary) && !summary.contains("\n") && !summary.isEmpty)
        #expect(StageHelp.help(stage, locale: locale)?.key == StageHelp.key(stage))
      }
    }
    // The summary follows the language: « Terminé » is French, "Done" English.
    #expect(StageHelp.card(.data, locale: Locale(identifier: "fr"))?.contains("Terminé") == true)
    #expect(StageHelp.card(.data, locale: Locale(identifier: "en"))?.contains("Done") == true)
  }

  @Test("every stage pane reports the stage's « ? », built or not", .scratchDirectory)
  func testEveryStagePaneShowsItsHelp() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    for stage in JourneyStage.allCases {
      model.select(stage)
      let ids = AccessibilityAuditTests.entries(ProjectWindowView(model: model)).map(\.id)
      #expect(ids.contains(StageHelp.key(stage).rawValue), "\(stage): \(ids)")
    }
  }
}
