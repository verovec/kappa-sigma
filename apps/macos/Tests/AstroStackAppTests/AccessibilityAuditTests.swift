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
    // 2 parameter rows × 3, 3 install cards × 2, 2 curve editors × 2.
    #expect(entries.count == 16, "\(entries.map(\.id))")
    #expect(entries.contains { $0.id == "fr.astrostack.parameter.haBlend.slider" })
  }

  @Test("the workspace: the journey stages and the stage pane's controls", .scratchDirectory)
  func testWorkspace() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let model = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    model.select(.data)
    let entries = Self.entries(ProjectWindowView(model: model))
    #expect(AccessibilityAudit.problems(entries) == [])
    let ids = Set(entries.map(\.id))
    #expect(
      ids.isSuperset(of: JourneyStage.allCases.map { "fr.astrostack.journey.\($0.rawValue)" }))
    #expect(ids.contains("fr.astrostack.stage.data.import"))
    #expect(entries.first { $0.id == "fr.astrostack.journey.data" }?.label == "Données")
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

  /// Sources whose interactive controls must all go through `.accessible`.
  nonisolated static let audited = [
    "RenderKit/DesignSystem/Components", "AstroStackApp/JourneySidebar.swift",
    "AstroStackApp/DataStagePane.swift", "AstroStackApp/ShortcutsSheet.swift",
    "AstroStackApp/GlossaryView.swift",
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
      let source = try String(contentsOf: file, encoding: .utf8)
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
