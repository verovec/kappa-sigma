import AppKit
import AstroStackApp
import Foundation
import HelpKit
import ProjectKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

/// The first-stack guide (card 0061): seven steps, each pointing at a control the app really
/// shows; closed until Help › First-Stack Guide, then on the step the project reached.
@MainActor
@Suite("First-stack guide — seven steps on real controls, opened only from Help")
struct FirstStackGuideTests {
  static func model(_ project: ProjectPackage) -> ProjectWindowModel {
    ProjectWindowModel(store: { project.store }, planning: { _ in ImportPlanningStub.empty })
  }

  @Test("every step points at an identifier a hosted view reports, and rings it", .scratchDirectory)
  func testStepsResolveToIdentifiers() async throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let model = Self.model(project)
    var reported: [String: AccessibilityAudit.Entry] = [:]
    for (index, step) in FirstStackGuide.steps.enumerated() {
      model.showGuideStep(index)
      #expect(model.selection == step.stage)
      let target = try #require(model.guideTarget)
      let profiles = await ImportProfileTests.model()
      let views: [AnyView] =
        [AnyView(ProjectWindowView(model: model)), AnyView(ImportProfileView(model: profiles))]
        + JourneyStage.allCases.map { AnyView(JourneySidebarRow(stage: $0, status: .toDo)) }
      for view in views {
        let entries = AccessibilityAuditTests.entries(view.environment(\.guideTarget, target))
        for entry in entries { reported[entry.id] = entry }
        #expect(entries.filter(\.highlighted).allSatisfy { $0.id == target.rawValue })
      }
      #expect(reported[target.rawValue]?.highlighted == true, "step \(index + 1): \(target)")
    }
    #expect(FirstStackGuide.steps.count == 7)
    #expect(AppGlossary.help.guideProblems(steps: FirstStackGuide.steps.count).isEmpty)
    for locale in ["fr", "en"] {
      #expect(!FirstStackGuide.text(6, locale: Locale(identifier: locale)).isEmpty)
    }
    #expect(FirstStackGuide.text(7, locale: Locale(identifier: "fr")).isEmpty)
  }

  @Test(
    "the guide never opens by itself; Help opens it on the step the project reached",
    .scratchDirectory)
  func testOpensOnlyFromHelp() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let project = try ProjectPackage.create(at: url)
    defer { try? project.close() }
    let model = Self.model(project)
    model.select(.stacking)
    model.refresh()
    #expect(model.guideStep == nil)
    #expect(model.guideTarget == nil)

    model.openGuide()
    #expect(model.guideStep == 0)
    #expect(model.selection == .data)
    model.showGuideStep(3)
    model.showGuideStep(7)
    #expect(model.guideStep == 3, "out of range: nothing")
    model.closeGuide()
    #expect(model.guideStep == nil)

    // A window reopened on this project: still closed, then back on step 4.
    let reopened = Self.model(project)
    #expect(reopened.guideStep == nil)
    #expect(reopened.selection == .stacking)
    reopened.openGuide()
    #expect(reopened.guideStep == 3)
    #expect(reopened.guideTarget == .stackingRun)
    try project.store.setSetting("guide.step", to: "42")
    reopened.openGuide()
    #expect(reopened.guideStep == 0, "an unknown step starts over")
  }

  @Test("the panel lays out each step in both languages, Back and Next at the ends greyed")
  func testPanelLaysOut() throws {
    let model = ProjectWindowModel(store: { nil }, planning: { _ in ImportPlanningStub.empty })
    for language in ["fr", "en"] {
      for step in [0, 6] {
        let entries = AccessibilityAuditTests.entries(
          GuidePanel(model: model, step: step), language: language)
        #expect(AccessibilityAudit.problems(entries) == [])
        #expect(entries.map(\.id) == ["back", "next", "close"].map { "fr.astrostack.guide.\($0)" })
      }
    }
    let host = NSHostingView(rootView: HelpText("**A** b\n- c").frame(width: 300))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height > 20)
  }
}
