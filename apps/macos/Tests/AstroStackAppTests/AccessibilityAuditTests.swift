import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

/// Every interactive control of the shared components and the workspace has a label and a stable
/// identifier (card 0079), checked on what the hosted views report — SwiftUI builds no
/// accessibility tree without an assistive client, so the audit reads `AccessibilityAudit.Key` —
/// and on the sources, where a raw control without `.accessible` would hide from the preference.
@MainActor
@Suite("Accessibility audit — every interactive element has a label and an identifier")
struct AccessibilityAuditTests {
  /// Collects what a hosted view reports.
  final class Reported {
    var entries: [AccessibilityAudit.Entry] = []
  }

  /// The entries `view` reports once laid out in `language`.
  static func entries<Content: View>(_ view: Content, language: String = "fr")
    -> [AccessibilityAudit.Entry]
  {
    let reported = Reported()
    let host = NSHostingView(
      rootView: view.environment(\.locale, Locale(identifier: language))
        .onPreferenceChange(AccessibilityAudit.Key.self) { reported.entries = $0 }
        .frame(width: 900, height: 1800))
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 1800)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    return reported.entries
  }

  @Test(
    "every interactive element has a label and an identifier: the gallery",
    arguments: ["en", "fr"])
  func testEveryInteractiveElementHasLabelAndIdentifier(language: String) {
    let entries = Self.entries(ComponentGallery(), language: language)
    #expect(AccessibilityAudit.problems(entries) == [])
    // 2 parameter rows × 4 (help, slider, field, reset), 4 install cards × 2, 2 curve editors × 2,
    // the stretch controls' 3 visible rows × 4 (the raw rows sit in a closed disclosure) and the
    // histogram canvas.
    #expect(entries.count == 33, "\(entries.map(\.id))")
    #expect(entries.contains { $0.id == "fr.astrostack.parameter.haBlend.slider" })
    #expect(entries.contains { $0.id == "fr.astrostack.parameter.gallery.shadowsSigma.slider" })
    #expect(entries.contains { $0.id == "fr.astrostack.histogram.gallery.canvas" })
  }

  @Test("the workspace: the journey stages and the stage pane's controls", .scratchDirectory)
  func testWorkspace() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    model.select(.data)
    let window = Self.entries(ProjectWindowView(model: model))
    // The stage's « ? » (card 0086) and its Import button.
    #expect(
      window.map(\.id) == ["fr.astrostack.help.stage.data", "fr.astrostack.stage.data.import"])
    // The sidebar's rows are table cells whose preferences stay in the List: each real row is
    // hosted on its own.
    let rows = JourneyStage.allCases.flatMap { stage in
      Self.entries(JourneySidebarRow(stage: stage, status: .toDo))
    }
    #expect(AccessibilityAudit.problems(window + rows) == [])
    #expect(rows.map(\.id) == JourneyStage.allCases.map { "fr.astrostack.journey.\($0.rawValue)" })
    #expect(rows.first?.label == "Données")
  }

  @Test("the workspace: the Stacking stage's preset and Run", .scratchDirectory)
  func testStackingStage() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    model.select(.stacking)
    let entries = Self.entries(ProjectWindowView(model: model))
    #expect(AccessibilityAudit.problems(entries) == [])
    #expect(
      Set(entries.map(\.id)).isSuperset(of: [
        "fr.astrostack.stage.stacking.preset", "fr.astrostack.stage.stacking.run",
      ]))
  }

  @Test("the audit fails a control without label, without identifier, or with a repeated one")
  func testAuditCatchesMissingLabel() {
    let entries = Self.entries(
      VStack {
        Button("A") {}.accessible(.fixture("labelled"), label: "Valider")
        Button("B") {}.accessible(.fixture("unlabelled"), verbatim: "")
        Button("C") {}.accessible(nil, verbatim: "Annuler")
        Button("D") {}.accessible(.fixture("labelled"), verbatim: "Encore")
      })
    #expect(
      AccessibilityAudit.problems(entries) == [
        "fr.astrostack.test.unlabelled: no label",
        "a control without identifier (« Annuler »)",
        "fr.astrostack.test.labelled: identifier used twice",
      ])
  }

  @Test("a control inside an announced container keeps its own entry")
  func testNestedEntriesKept() {
    let entries = Self.entries(
      HStack {
        Button("A") {}.accessible(.fixture("inner"), verbatim: "Intérieur")
      }
      .accessible(.fixture("outer"), verbatim: "Extérieur"))
    #expect(Set(entries.map(\.id)) == ["fr.astrostack.test.inner", "fr.astrostack.test.outer"])
  }

  /// Sources whose interactive controls must all go through `.accessible`.
  nonisolated static let audited = [
    "RenderKit/DesignSystem/Components", "RenderKit/Viewer/STFControls.swift",
    "AstroStackApp/JourneySidebarRow.swift",
    "AstroStackApp/DataStagePane.swift", "AstroStackApp/StackingStagePane.swift",
    "AstroStackApp/StackingSeriesView.swift", "AstroStackApp/StudioStagePane.swift",
    "AstroStackApp/CalibrationStagePane.swift",
    "AstroStackApp/KnobPanel.swift", "AstroStackApp/KnobRow.swift",
    "AstroStackApp/ShortcutsSheet.swift", "AstroStackApp/StudioCatalogueView.swift",
    "AstroStackApp/StudioSideView.swift", "AstroStackApp/ProcessPanel.swift",
    "AstroStackApp/ProcessParameterRow.swift", "AstroStackApp/StudioMaskRow.swift",
    "AstroStackApp/StudioCatalogueRow.swift", "AstroStackApp/ProcessHistogramExtras.swift",
    "AstroStackApp/PipelineSidebarView.swift", "AstroStackApp/PipelineStepRow.swift",
    "AstroStackApp/PipelineDiffSheet.swift", "AstroStackApp/ReplayChooser.swift",
    "AstroStackApp/GlossaryView.swift", "AstroStackApp/GuidePanel.swift",
    "AstroStackApp/ReviewStagePane.swift", "AstroStackApp/FrameReviewView.swift",
    "AstroStackApp/FrameTable.swift", "AstroStackApp/FrameBlinkView.swift",
    "AstroStackApp/StackPicker.swift", "AstroStackApp/ExportStagePane.swift",
    "AstroStackApp/ExportStageView.swift", "AstroStackApp/ExportForm.swift",
    "AstroStackApp/ExportRecordList.swift", "AstroStackApp/ExportRecordRow.swift",
    "AstroStackApp/StarSeparationSection.swift", "AstroStackApp/StarSeparationButton.swift",
    "AstroStackApp/StarSeparationSheet.swift", "AstroStackApp/StudioChannelSwitcher.swift",
    "AstroStackApp/ObjectsSection.swift", "AstroStackApp/ObjectCard.swift",
  ]

  @Test("no raw control: each audited source has as many `.accessible` as controls")
  func testSourcesDeclareEveryControl() throws {
    let root = try ModuleBoundary.packageRoot(from: #filePath) + "/Sources/"
    var files: [URL] = []
    for path in Self.audited {
      let url = URL(fileURLWithPath: root + path)
      if path.hasSuffix(".swift") {
        files.append(url)
      } else {
        let found =
          FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
          .allObjects as? [URL] ?? []
        files += found.filter { $0.pathExtension == "swift" }
      }
    }
    #expect(files.count >= 12)
    for file in files {
      // Comments are not code: a `.accessible(` or a `Button(` in a doc line counts for nothing.
      let source = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
      let controls = Self.count(
        #"\b(Button|Slider|TextField|Toggle|Picker|Link|Stepper)\s*[({]"#, in: source)
      // The sidebar's rows are its controls: one `.accessible` per row covers the List.
      let declared = Self.count(#"\.accessible\("#, in: source)
      #expect(
        declared >= controls,
        "\(file.lastPathComponent): \(controls) controls, \(declared) declared")
    }
  }

  nonisolated static func count(_ pattern: String, in source: String) -> Int {
    (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(
      in: source, range: NSRange(source.startIndex..., in: source)) ?? 0
  }
}
