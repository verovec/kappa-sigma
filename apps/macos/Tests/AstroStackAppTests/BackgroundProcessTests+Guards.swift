import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import StackKit
import Synchronization
import TestSupport
import Testing

extension BackgroundProcessTests {
  /// Something the fake engine does on the main actor while it runs (an undo meanwhile).
  final class During: Sendable {
    private let storage = Mutex<(@MainActor @Sendable () -> Void)?>(nil)
    func set(_ action: @escaping @MainActor @Sendable () -> Void) {
      storage.withLock { $0 = action }
    }
    @MainActor func run() { storage.withLock { $0 }?() }
  }

  static func tools(during: During, calls: Calls) -> StudioTools {
    let plain = tools(calls: calls)
    return StudioTools(locate: plain.locate) { image, params, progress in
      await during.run()
      return try await plain.background(image, params, progress)
    }
  }

  @Test(
    "a head moved while the tool ran: the result is refused, the history kept", .scratchDirectory)
  func testHeadMovedDuringRun() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = During()
    let workspace = try Self.workspace(opened, tools: Self.tools(during: during, calls: Calls()))
    try workspace.studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    during.set { try? workspace.studio.undo() }
    workspace.choose(BackgroundExtractionProcess.id)
    await workspace.runBatch()
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"])
    var failure = try #require(workspace.failure)
    failure.locale = Locale(identifier: "en")
    #expect(String(localized: failure).hasPrefix("The image changed while"))
  }

  @Test("one run at a time; undo waits for it; Siril cannot divide", .scratchDirectory)
  func testOneRunAtATime() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let calls = Calls()
    let during = During()
    let workspace = try Self.workspace(opened, tools: Self.tools(during: during, calls: calls))
    workspace.choose(BackgroundExtractionProcess.id)
    during.set {
      // A second Apply and an undo while the first runs: neither acts.
      workspace.startBatch()
      #expect(throws: StudioError.toolRunning) { try workspace.undo() }
    }
    await workspace.runBatch()
    #expect(calls.engines == ["graxpert"])
    #expect(workspace.studio.steps.count == 2)

    let panel = try #require(workspace.panel)
    panel.set("engine", .choice("siril-rbf"))
    panel.set("correction", .choice("divide"))
    #expect(panel.unavailableOptions["correction"]?["divide"] != nil)
    await workspace.runBatch()
    #expect(calls.engines == ["graxpert"], "refused before any tool")
    #expect(workspace.failure != nil)
  }

  @Test("an undo during a started run cancels it, records nothing and undoes", .scratchDirectory)
  func testUndoCancelsRun() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = During()
    let calls = Calls()
    let workspace = try Self.workspace(opened, tools: Self.tools(during: during, calls: calls))
    try workspace.studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    during.set { try? workspace.undo() }
    workspace.choose(BackgroundExtractionProcess.id)
    workspace.startBatch()
    await workspace.batchTask?.value
    #expect(calls.engines == ["graxpert"])
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"], "stretch undone")
    #expect(workspace.failure == nil && workspace.batchProgress == nil)
  }

  @Test("choosing or closing leaves no model view and no stale preview", .scratchDirectory)
  func testNoStaleView() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, tools: Self.tools())
    workspace.choose(BackgroundExtractionProcess.id)
    await workspace.runBatch()
    try workspace.toggleModel()
    workspace.closePanel()
    #expect(!workspace.showsModel)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes)

    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    #expect(workspace.isPreviewing)
    workspace.choose(BackgroundExtractionProcess.id)
    #expect(!workspace.isPreviewing)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes)
  }
}
