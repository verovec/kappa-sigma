import AppKit
import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

extension ProjectDocumentTests {
  /// Without a window the Studio and Tri commands do nothing and their menu items are off:
  /// Apply needs an open panel on the Studio stage, keep / reject / continue the Tri stage.
  @Test("Studio and Tri commands without a window: no effect, menu items off", .scratchDirectory)
  func testCommandsWithoutWindow() throws {
    let document = try ProjectDocument(type: Self.type)
    defer { document.close() }
    document.showGuide(nil)
    document.applyProcess(nil)
    document.blinkPrevious(nil)
    document.blinkNext(nil)
    document.keepFrame(nil)
    document.rejectFrame(nil)
    document.continueStacking(nil)
    let off: [Selector] = [
      #selector(ProjectDocument.applyProcess(_:)), #selector(ProjectDocument.keepFrame(_:)),
      #selector(ProjectDocument.rejectFrame(_:)), #selector(ProjectDocument.blinkNext(_:)),
      #selector(ProjectDocument.blinkPrevious(_:)),
      #selector(ProjectDocument.continueStacking(_:)),
    ]
    for action in off {
      let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
      #expect(!document.validateUserInterfaceItem(item), "\(action)")
    }
    let save = NSMenuItem(
      title: "", action: #selector(NSDocument.save(_:)), keyEquivalent: "")
    _ = document.validateUserInterfaceItem(save)
  }
}

extension ProjectDocumentTests {
  /// Card 0088: without a window (no Studio, no pipeline) the pipeline commands are off and do
  /// nothing.
  @Test("pipeline commands without a window: no effect, menu items off", .scratchDirectory)
  func testPipelineCommandsWithoutWindow() throws {
    let document = try ProjectDocument(type: Self.type)
    defer { document.close() }
    document.runPipeline(nil)
    document.continuePipeline(nil)
    document.replayPipeline(nil)
    for action in [
      #selector(ProjectDocument.runPipeline(_:)), #selector(ProjectDocument.continuePipeline(_:)),
      #selector(ProjectDocument.replayPipeline(_:)),
    ] {
      let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
      #expect(!document.validateUserInterfaceItem(item), "\(action)")
    }
  }
}

extension ProjectDocumentTests {
  /// The four of card 0105, through the document's own list (one is never forgotten).
  static let geometryActions = ProjectDocument.geometryActions

  /// Card 0105: without a window the rotate and flip commands are off and do nothing.
  @Test("geometry commands without a window: no effect, menu items off", .scratchDirectory)
  func testGeometryCommandsWithoutWindow() throws {
    #expect(Self.geometryActions.count == 4)
    let document = try ProjectDocument(type: Self.type)
    defer { document.close() }
    document.rotateImageClockwise(nil)
    document.flipImageVertically(nil)
    for action in Self.geometryActions {
      let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
      #expect(!document.validateUserInterfaceItem(item), "\(action)")
    }
  }

  /// Card 0105 through the document: on the Studio stage the menu items reach the workspace's
  /// geometry panel (nothing applied); on another stage they are greyed.
  @Test(
    "geometry commands reach the Studio's panel, greyed on another stage", .scratchDirectory,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testGeometryCommandsOnStack() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let package = try ProjectPackage.create(at: url)
    let output = url.appendingPathComponent("stacks/A")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    _ = try ProjectTests.writeBundle(in: output, runID: "A")
    _ = try package.store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", object: "M 31", scopeJSON: nil)
    try package.close()

    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    defer { document.close() }
    document.makeWindowControllers()
    let window = try #require(document.windowModel)
    window.refresh()
    window.select(.studio)
    await window.openStudio()
    await ProjectWindowWorkspaceTests.settle { window.workspace != nil }
    func enabled(_ action: Selector) -> Bool {
      document.validateUserInterfaceItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
    }
    for action in Self.geometryActions { #expect(enabled(action), "\(action)") }

    document.rotateImageClockwise(nil)
    document.flipImageHorizontally(nil)
    let panel = try #require(window.workspace?.panel)
    #expect(panel.type.id == GeometryProcess.id)
    #expect(panel.params.choice("rotation") == "90" && panel.params.flag("flipH"))
    document.rotateImageCounterclockwise(nil)
    document.flipImageVertically(nil)
    #expect(GeometryProcess.isIdentity(panel.params), "back to the shown original")
    #expect(window.workspace?.studio.steps.count == 1, "nothing applied")

    window.select(.data)
    for action in Self.geometryActions { #expect(!enabled(action), "\(action)") }
  }
}
