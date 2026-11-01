import AppKit
import AstroStackApp
import Foundation
import HelpKit
import ProcessKit
import RenderKit
import SwiftUI
import Testing

/// Card 0159: the side column of an edit — its header, Cancel / Apply change instead of Close /
/// Apply, each history row's eye, the Versions menu — with an identifier per control; the
/// re-edit help card and the « version » term in fr and en.
extension StudioViewsTests {
  @Test("an edit shows its own buttons, each row its eye, the Versions menu", .scratchDirectory)
  func testSideColumn_Edit() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.edited(opened)
    let undoManager = StudioUndoRunTests.undoManager()
    workspace.editStep(1)
    try #require(workspace.panel).set("targetBackground", .number(0.4))
    await StudioUndo.applyEdit(workspace, on: undoManager)
    workspace.editStep(1)
    await workspace.settlePreview()

    let entries = AccessibilityAuditTests.entries(StudioSideView(model: workspace))
    let ids = Set(entries.map(\.id))

    for id in ["edit.cancel", "edit.apply", "step.1.compare", "versions", "step.0"] {
      #expect(ids.contains("fr.astrostack.stage.studio." + id), "\(id)")
    }
    #expect(!ids.contains("fr.astrostack.stage.studio.apply"), "the head's Apply is hidden")
    #expect(AccessibilityAudit.problems(entries) == [])
    let host = NSHostingView(rootView: StudioSideView(model: workspace).frame(width: 320))
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 900)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height > 0)
  }

  @Test("the re-edit help card and the « version » term exist in fr and en")
  func testReEditHelp() {
    #expect(AppGlossary.help.coverageProblems(stages: ["re-edit"]).isEmpty)
    #expect(AppGlossary.termIDs.contains("studio.version"))
    for language in ["fr", "en"] {
      #expect(
        StageHelp.help(card: "re-edit", locale: Locale(identifier: language)) != nil, "\(language)")
      #expect(
        AppGlossary.label("studio.version", locale: Locale(identifier: language)) == "Version")
    }
  }
}

extension StudioViewsTests {
  @Test("a version's actions: compare, restore, drop greyed with its reason", .scratchDirectory)
  func testVersionActions() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.edited(opened)
    try await workspace.studio.reviseStep(1, params: try StudioModelTests.stretch(target: 0.4))
    let version = try #require(workspace.versions.last)

    let ids = AccessibilityAuditTests.entries(
      StudioVersionActions(model: workspace, index: 0, version: version) { _ in }
    ).map(\.id)

    #expect(
      ids == ["compare", "restore", "drop"].map { "fr.astrostack.stage.studio.versions.0." + $0 })
  }
}

extension StudioViewsTests {
  @Test(
    "the edit header names the stop and the recorded mask; a failure shows beside it",
    .scratchDirectory)
  func testEditHeader_StopMaskAndFailure() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    try studio.apply(StretchProcess.id, params: try StudioModelTests.stretch(target: 0.2))
    try studio.apply(
      SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema),
      mask: StudioWorkspaceModelTests.halfMask(studio))
    try studio.apply(
      BackgroundExtractionProcess.id, params: ParamSet(schema: BackgroundExtractionProcess.schema),
      result: studio.head)
    try studio.apply(SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema))
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color])
    workspace.editStep(2)
    await workspace.settlePreview()
    workspace.editStep(99)

    #expect(workspace.editedStep == 2 && workspace.chainStoppedBefore == 3)
    #expect(workspace.editUsesRecordedMask && workspace.failure != nil)
    let entries = AccessibilityAuditTests.entries(StudioSideView(model: workspace))
    #expect(Set(entries.map(\.id)).contains("fr.astrostack.stage.studio.edit.apply"))
    #expect(AccessibilityAudit.problems(entries) == [])
  }

  @Test("a row click edits, ⌥-click and a branch's rows compare", .scratchDirectory)
  func testClickStep() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: BranchTests.bundle())
    try workspace.studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))

    workspace.clickStep(0, option: true)
    #expect(workspace.comparing == 0 && workspace.editing == nil)
    workspace.clickStep(1, option: false)
    #expect(workspace.editing == 1)
    workspace.cancelEdit()
    workspace.select(.branch("Ha"))
    workspace.clickStep(0, option: false)
    let refusal = String(
      localized: .app("Only the combined image's steps can be edited: show it first."))
    #expect(workspace.editing == nil, "compared (no step there), never edited")
    #expect(workspace.failure.map { String(localized: $0) } != refusal)
  }

  @Test("the drop confirmation says what it frees, in fr and en", .scratchDirectory)
  func testDropMessage() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.edited(opened)
    try await workspace.studio.reviseStep(1, params: try StudioModelTests.stretch(target: 0.4))
    let id = try #require(workspace.versions.last).id

    let fr = String(localized: workspace.dropMessage(id, locale: Locale(identifier: "fr")))
    let en = String(localized: workspace.dropMessage(id, locale: Locale(identifier: "en")))

    #expect(fr.hasPrefix("Supprime ses étapes et fichiers (") && fr.hasSuffix("l’image combinée."))
    #expect(en.hasPrefix("Deletes its steps and files ("))
  }
}
