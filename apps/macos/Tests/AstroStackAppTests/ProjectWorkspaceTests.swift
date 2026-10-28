import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

/// The project window as a journey: a sidebar of stages with their states, the selected stage's
/// pane, in each language and appearance; the selected stage restored per project.
@MainActor
@Suite("Project workspace — journey sidebar and stage panes")
struct ProjectWorkspaceTests {
  struct Variant: Sendable, CustomTestStringConvertible {
    let stage: JourneyStage
    let language: String
    let appearance: DesignAppearance
    var testDescription: String { "\(stage)-\(language)-\(appearance)" }
  }

  nonisolated static let variants = JourneyStage.allCases.flatMap { stage in
    ["en", "fr"].flatMap { language in
      DesignAppearance.allCases.map { Variant(stage: stage, language: language, appearance: $0) }
    }
  }

  static func project(_ name: String = "M31") throws -> ProjectPackage {
    try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("\(name).astrostack"))
  }

  @Test(
    "every stage lays out, in fr and en, light and dark", .scratchDirectory, arguments: variants)
  func testEveryStageLaysOut(_ variant: Variant) throws {
    let project = try Self.project()
    defer { try? project.close() }
    try project.store.addSource(kind: .night, path: "/captures/M31/2026-10-18")
    // The project's folder names the switcher at the head of the sidebar (card 0146).
    let model = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      planning: { _ in ImportPlanningStub.empty })
    model.select(variant.stage)
    #expect(model.targetName == "M31")

    let host = ImportSheetTests.host(
      ProjectWindowView(model: model)
        .environment(\.locale, Locale(identifier: variant.language)))
    host.appearance = variant.appearance.nsAppearance
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 640 && host.fittingSize.height >= 400)
    if variant.stage == .data && variant.appearance == .light {
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      Attachment.record(png, named: "project-workspace-\(variant.language).png")
    }
  }

  @Test("the selected stage is restored per project", .scratchDirectory)
  func testSelectedStagePersistsPerProject() throws {
    let m31 = try Self.project("M31")
    let ic1848 = try Self.project("IC1848")
    defer { try? ic1848.close() }
    ProjectWindowModel(store: { m31.store }, planning: { _ in ImportPlanningStub.empty })
      .select(.stacking)
    try m31.close()

    let reopened = try ProjectPackage.open(at: m31.url)
    defer { try? reopened.close() }
    let again = ProjectWindowModel(
      store: { reopened.store }, planning: { _ in ImportPlanningStub.empty })
    #expect(again.selection == .stacking)
    let other = ProjectWindowModel(
      store: { ic1848.store }, planning: { _ in ImportPlanningStub.empty })
    #expect(other.selection == .data, "each project keeps its own stage")
  }

  @Test("every stage status has a badge and words in each language", arguments: ["en", "fr"])
  func testStatusWords(_ language: String) {
    let statuses: [StageStatus] = [
      .toDo, .ready, .running, .attention(3), .done, .unavailable(.needsSources),
      .unavailable(.needsStack),
    ]
    let locale = Locale(identifier: language)
    let words = statuses.map { String(localized: StagePane.words(for: $0, locale: locale)) }
    #expect(Set(words).count == statuses.count, "\(words)")
    #expect(words[3].contains("3"))
    #expect(StagePane.badge(for: .done) == .ok && StagePane.badge(for: .attention(1)) == .attention)
  }
}
