import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Synchronization
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
  }
}

/// Card 0093 review: the tool without Siril, and the same tool as a pipeline step.
@MainActor
@Suite(
  "Plate solving — greyed without Siril, one tool for the pipeline",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct PlateSolveToolWiringTests {
  @Test("no Siril: no tool, the catalogue greys plate solving with the reason", .scratchDirectory)
  func testGreyedWithoutSiril() throws {
    let scratch = try ScratchDirectory.url
    #expect(StudioTool.standard(scratch: scratch, sirilInstalled: false).isEmpty)
    #expect(
      StudioTool.standard(scratch: scratch, sirilInstalled: true).keys.sorted() == ["plate-solve"])
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

  @Test("the Studio tool runs as a pipeline step, its percent as progress", .scratchDirectory)
  func testBatchProcess() async throws {
    let tool = StudioTool { image, _, onProgress in
      onProgress(ToolProgress(line: "half", percent: 50))
      image.planes = image.planes.map { $0.map { $0 + 1 } }
      return StudioToolResult(image: image, report: nil)
    }
    let batch = tool.batchProcess(schema: PlateSolveProcess.schema)
    let image = AstroImage(
      width: 1, height: 1, planes: [[0.25]], metadata: ImageMetadata(rowOrder: .topDown))
    let seen = Mutex<[Double]>([])
    let result = try await batch.run(image, ParamSet(schema: PlateSolveProcess.schema)) { value in
      seen.withLock { $0.append(value) }
    }
    #expect(result.planes == [[1.25]] && image.planes == [[0.25]], "the caller's image untouched")
    #expect(seen.withLock { $0 } == [0.5])
  }
}
