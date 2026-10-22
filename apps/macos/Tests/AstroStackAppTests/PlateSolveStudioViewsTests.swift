import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0093 on screen and on the undo manager: the run shows its Stop, the report follows, ⌘Z
/// takes back the recorded solve; every failure reads as a sentence.
@MainActor
@Suite(
  "Plate solving — the side column, the undo manager, the sentences",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct PlateSolveStudioViewsTests {
  @Test(
    "a run shows Stop; the report replaces it; Apply goes through the undo manager",
    .scratchDirectory)
  func testSideColumnAndUndo() async throws {
    let gate = AsyncStream<Void>.makeStream()
    let tool = StudioTool { image, _, onProgress in
      onProgress(ToolProgress(line: "Findstar: processing for channel 1...", percent: nil))
      for await _ in gate.stream { break }
      return StudioToolResult(image: image) { _ in .app("Stopped: nothing was recorded.") }
    }
    let opened = try PlateSolveProcessTests.open(tools: [PlateSolveProcess.id: tool])
    defer { try? opened.project.package.close() }
    let workspace = opened.workspace
    workspace.choose(PlateSolveProcess.id)
    let undoManager = UndoManager()

    await withCheckedContinuation { done in
      StudioUndo.apply(workspace, undoManager: undoManager) { done.resume() }
      Task { @MainActor in
        await Task.yield()
        let running = Set(
          AccessibilityAuditTests.entries(StudioSideView(model: workspace)).map(\.id))
        #expect(running.contains(AccessibilityID.studioToolStop.rawValue))
        gate.continuation.yield()
      }
    }
    #expect(workspace.studio.steps.last?.processID == PlateSolveProcess.id)
    #expect(workspace.toolReport != nil)
    let after = Set(AccessibilityAuditTests.entries(StudioSideView(model: workspace)).map(\.id))
    #expect(!after.contains(AccessibilityID.studioToolStop.rawValue))
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(workspace.studio.steps.last?.processID == ChannelCombinationProcess.id)
  }

  @Test(
    "every plate-solve failure is a sentence of its own, in both languages",
    arguments: [
      UserFacingError.plateSolve(.failed(reason: "no stars")),
      .plateSolve(.catalogueMissing(path: "/x/cat.dat")),
      .plateSolve(.noSolution(path: "/x/solved.fits")),
      .plateSolveInput(.coordinatesMissing), .plateSolveInput(.unreadable("north")),
      .plateSolveInput(.opticsMissing), .studio(.needsTool("plate-solve")),
      .pipeline(.unknownProcess("x")), .pipeline(.noStep(2)),
      .pipeline(.notAtBreakpoint(step: 1, steps: 3)),
      .pipeline(.invalidValues(step: 0, ids: ["gain"])), .pipeline(.toolMissing("plate-solve")),
    ])
  func testSentences(error: UserFacingError) {
    var english = error.message
    english.locale = Locale(identifier: "en")
    var french = error.message
    french.locale = Locale(identifier: "fr")
    #expect(!String(localized: english).isEmpty)
    #expect(String(localized: english) != String(localized: french))
  }

  @Test("the kit errors map to their sentences")
  func testMapping() {
    #expect(
      UserFacingError(PlateSolveError.noSolution(path: "p")) == .plateSolve(.noSolution(path: "p")))
    #expect(
      UserFacingError(PlateSolveTool.InputError.opticsMissing) == .plateSolveInput(.opticsMissing))
    #expect(UserFacingError(PipelineError.noStep(1)) == .pipeline(.noStep(1)))
  }
}

/// Card 0093 review: the tool without Siril.
@MainActor
@Suite(
  "Plate solving — greyed without Siril",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct PlateSolveToolWiringTests {
  @Test("no Siril: no tool, the catalogue greys plate solving with the reason", .scratchDirectory)
  func testGreyedWithoutSiril() throws {
    let scratch = try ScratchDirectory.url
    #expect(StudioTool.standard(scratch: scratch, sirilInstalled: false).isEmpty)
    #expect(
      StudioTool.standard(scratch: scratch, sirilInstalled: true).keys.sorted() == [
        "colour-calibration", "plate-solve",
      ])
    let opened = try PlateSolveProcessTests.open(tools: [:])
    defer { try? opened.project.package.close() }
    let entry = opened.workspace.catalogue.flatMap(\.entries).first {
      $0.id == PlateSolveProcess.id
    }
    #expect(entry?.unavailable == .toolMissing)
    #expect(
      StudioCatalogueView.reason(.toolMissing, locale: Locale(identifier: "fr"))
        == "Requiert Siril, introuvable : installez-le, puis rouvrez le projet")
  }

}
