import AppKit
import AstroStackApp
import Foundation
import HelpKit
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// The branch workspace (card 0119): a channel switcher routes the viewer, the panel, Apply and
/// ⌘Z to the chosen history; a branch greys what it cannot take; the combined view says which
/// steps a branch edit outdated and replays them on request.
extension StudioWorkspaceModelTests {
  @Test(
    "testSelectionRoutesApplyAndUndo", .scratchDirectory,
    arguments: [StudioSelection.main, .branch("RGB"), .branch("Ha")])
  func testSelectionRoutesApplyAndUndo(selection: StudioSelection) async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    let studio = workspace.studio
    let main = studio.steps
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false

    workspace.select(selection)
    workspace.choose(DenoiseProcess.id, params: try BranchTests.denoise())
    await workspace.previewNow()
    undoManager.beginUndoGrouping()
    StudioUndo.apply(workspace, undoManager: undoManager)
    undoManager.endUndoGrouping()

    #expect(workspace.failure == nil)
    #expect(workspace.steps.map(\.processID).last == DenoiseProcess.id)
    #expect(workspace.viewer.model.image.planes == studio.head(of: selection).planes)
    for id in ["RGB", "Ha", "OIII"] {
      let edited = selection == .branch(id)
      #expect(studio.steps(of: .branch(id)).count == (edited ? 1 : 0), "\(id) only if chosen")
    }
    #expect(studio.steps.count == main.count + (selection == .main ? 1 : 0))

    undoManager.undo()
    #expect(studio.steps == main)
    for id in ["RGB", "Ha", "OIII"] { #expect(studio.steps(of: .branch(id)).isEmpty) }
    #expect(workspace.selection == selection, "⌘Z undoes where the step was made")
  }

  @Test("testBranchCatalogueGreysNonBranchable", .scratchDirectory)
  func testBranchCatalogueGreysNonBranchable() throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    func reasons() -> [String: StudioUnavailable?] {
      let entries = workspace.catalogue.flatMap(\.entries)
      return Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.unavailable) })
    }

    workspace.select(.branch("Ha"))
    let line = reasons()
    #expect(line.count == workspace.registry.types.count, "nothing hidden (R2)")
    #expect(line[StretchProcess.id] == .onCombinedImage)
    #expect(line[GeometryProcess.id] == .onCombinedImage)
    #expect(line[ChannelCombinationProcess.id] == .onCombinedImage)
    #expect(line[ColourBalanceProcess.id] == .needsColourLayer)
    #expect(line[DenoiseProcess.id] == .some(nil))
    workspace.select(.branch("RGB"))
    #expect(reasons()[ColourBalanceProcess.id] == .some(nil))
    #expect(reasons()[ColourCalibrationProcess.id] == .toolOnCombinedImage)
    workspace.select(.main)
    #expect(reasons()[StretchProcess.id] == .some(nil))

    for language in ["en", "fr"] {
      let locale = Locale(identifier: language)
      for reason in [StudioUnavailable.onCombinedImage, .needsColourLayer] {
        #expect(!StudioCatalogueView.reason(reason, locale: locale).isEmpty)
      }
    }
    #expect(
      StudioCatalogueView.reason(.onCombinedImage, locale: Locale(identifier: "fr"))
        .contains("combinée"))
  }

  @Test("the history's Undo on a branch never replays the combined image's ⌘Z", .scratchDirectory)
  func testBranchUndoButtonKeepsToItsHistory() async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    undoManager.beginUndoGrouping()
    StudioUndo.apply(workspace, undoManager: undoManager)
    undoManager.endUndoGrouping()
    let main = workspace.studio.steps

    workspace.select(.branch("Ha"))
    StudioUndo.undo(workspace, undoManager: undoManager)

    #expect(workspace.studio.steps == main, "the stretch is still applied")
    #expect(workspace.selection == .branch("Ha"))
    #expect(undoManager.canUndo, "⌘Z still names the stretch")
  }

  @Test("testStaleBannerAndReplay", .scratchDirectory)
  func testStaleBannerAndReplay() async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    try StudioModelBranchTests.finish(workspace.studio)
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: Pipeline(name: "finish", steps: []),
      store: opened.package.store, base: [.color, .emission])
    workspace.pipeline = sidebar
    #expect(workspace.staleNotice == nil)

    workspace.select(.branch("Ha"))
    workspace.choose(DenoiseProcess.id, params: try BranchTests.denoise())
    await workspace.previewNow()
    try workspace.apply()
    #expect(workspace.staleNotice == nil, "the banner is the combined view's")

    workspace.select(.main)
    #expect(workspace.staleNotice == StaleNotice(steps: [2], branches: ["Ha"]))
    #expect(sidebar.status(of: 1) == .done)
    #expect(sidebar.status(of: 2) == .stale)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    try await StudioUndo.replayMain(workspace, on: undoManager)
    #expect(workspace.staleNotice == nil)
    #expect(sidebar.status(of: 2) == .done)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes)
  }

  @Test("testSingleLayerBundleHasNoSwitcher", .scratchDirectory)
  func testSingleLayerBundleHasNoSwitcher() throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    // The same stack opened over its RGB layer alone: nothing to switch to.
    let single = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder.appendingPathComponent("single"),
      bundle: StudioModelTests.bundle())
    #expect(try StudioWorkspaceModel(studio: single, base: [.color]).selections.isEmpty)

    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    #expect(workspace.selections == [.main, .branch("RGB"), .branch("Ha"), .branch("OIII")])
    // Words from the glossary, never a raw id; the card the switcher's « ? » opens.
    for language in ["en", "fr"] {
      let locale = Locale(identifier: language)
      for selection in workspace.selections {
        #expect(!StudioSelection.label(selection, locale: locale).isEmpty)
      }
    }
    #expect(StudioSelection.label(.branch("Ha"), locale: Locale(identifier: "en")) != "Ha")
    #expect(AppGlossary.help.coverageProblems(stages: [StudioSelection.helpCard]).isEmpty)
  }
}
