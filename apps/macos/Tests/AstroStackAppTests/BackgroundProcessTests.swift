import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Background extraction in the Studio (card 0092), on card 0093's host-tool seam, over fake
/// engines: Apply runs the chosen engine and records one step with the model as an output, the
/// Model toggle shows it, a missing tool is named and never replaced by another engine (R2).
@MainActor
@Suite(
  "Background extraction in the Studio — step, model view, no fallback, chosen layers",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct BackgroundProcessTests {
  /// The engines the fake tool was asked for, in order.
  final class Calls: Sendable {
    private let storage = Mutex<[String]>([])
    var engines: [String] { storage.withLock { $0 } }
    func record(_ engine: String) { storage.withLock { $0.append(engine) } }
  }

  /// Something the fake engine does on the main actor while it runs (an undo meanwhile).
  final class During: Sendable {
    private let storage = Mutex<(@MainActor @Sendable () -> Void)?>(nil)
    func set(_ action: @escaping @MainActor @Sendable () -> Void) {
      storage.withLock { $0 = action }
    }
    @MainActor func run() { storage.withLock { $0 }?() }
  }

  /// The tool over a fake engine: corrected = image − 0.01, model = 0.01 (the real targets and
  /// step assembly of `BackgroundExtractionProcess.run`).
  static func tool(calls: Calls = Calls(), during: During = During()) -> StudioTool {
    StudioTool { input, params, onProgress in
      let extract: BackgroundExtractionProcess.Extract = { image, params, _ in
        calls.record(params.choice("engine"))
        await during.run()
        onProgress(ToolProgress(line: "fake 100%", percent: 100))
        let corrected = AstroImage(
          width: image.width, height: image.height,
          planes: image.planes.map { $0.map { $0 - 0.01 } }, metadata: image.metadata)
        let model = AstroImage(
          width: image.width, height: image.height,
          planes: image.planes.map { $0.map { _ in 0.01 } }, metadata: image.metadata)
        return (corrected, model)
      }
      let output = try await BackgroundExtractionProcess.run(
        input, params: params, extract: extract)
      return StudioToolResult(
        image: output.result, report: nil, outputs: output.outputs, replaced: output.replaced)
    }
  }

  /// A machine where `missing` is not installed.
  static func locate(missing: Set<HostTool> = []) -> @Sendable (HostTool) async -> ToolStatus {
    { tool in
      missing.contains(tool)
        ? .missing(path: "/Applications/\(tool.productName).app")
        : .found(path: "/usr/local/bin/\(tool.rawValue)", version: nil)
    }
  }

  /// The fake stack with two line layers.
  static func bundle() -> PipelineBundle {
    var bundle = StudioModelTests.bundle()
    let size = StudioModelTests.size
    for (id, value) in [("Ha", Float(0.3)), ("OIII", Float(0.2))] {
      let line = AstroImage(
        width: size, height: size, planes: [[Float](repeating: value, count: size * size)],
        metadata: ImageMetadata(rowOrder: .topDown))
      bundle.layers[id] = line
      bundle.layerStats[id] = StudioSession.stats(of: line)
    }
    return bundle
  }

  static func workspace(
    _ opened: StudioModelTests.Opened, tool: StudioTool = tool(), missing: Set<HostTool> = []
  ) throws -> StudioWorkspaceModel {
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: bundle())
    return try StudioWorkspaceModel(
      studio: studio, base: [.color, .emission], tools: [BackgroundExtractionProcess.id: tool],
      locate: locate(missing: missing))
  }

  @Test("testStepOutputsAndModelToggle", .scratchDirectory)
  func testStepOutputsAndModelToggle() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened)
    let combined = workspace.studio.head.planes
    #expect(!workspace.canShowModel)

    workspace.choose(BackgroundExtractionProcess.id)
    await workspace.refreshTools()
    let panel = try #require(workspace.panel)
    panel.set("applyTo", .choice("all"))
    #expect(await workspace.runTool())
    #expect(workspace.failure == nil && workspace.toolRun == nil)
    #expect(workspace.studio.steps.map(\.processID).last == BackgroundExtractionProcess.id)
    let step = try #require(workspace.studio.steps.last)
    #expect(step.outputs.keys.map(\.self) == [.backgroundModel])
    #expect(step.replaced.keys.sorted() == ["Ha", "OIII", "RGB"])
    let head = workspace.studio.head.planes
    #expect(head[0][0] == combined[0][0] - 0.01)

    // The Model toggle swaps the viewer to the model, then back to the head.
    #expect(workspace.canShowModel)
    try workspace.toggleModel()
    #expect(
      workspace.showsModel && workspace.viewer.model.image.planes[0].allSatisfy { $0 == 0.01 })
    try workspace.toggleModel()
    #expect(!workspace.showsModel && workspace.viewer.model.image.planes == head)

    // Undo restores the input and removes the outputs.
    try workspace.toggleModel()
    try workspace.undo()
    #expect(workspace.studio.head.planes == combined)
    #expect(!workspace.canShowModel && !workspace.showsModel)
    #expect(workspace.viewer.model.image.planes == combined)
    #expect(!workspace.studio.session.layerIDs().contains("backgroundModel"))
  }

  @Test("testNoFallbackWhenToolMissing", .scratchDirectory)
  func testNoFallbackWhenToolMissing() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let calls = Calls()
    let workspace = try Self.workspace(opened, tool: Self.tool(calls: calls), missing: [.graxpert])
    workspace.choose(BackgroundExtractionProcess.id)
    await workspace.refreshTools()
    let panel = try #require(workspace.panel)

    let english = Locale(identifier: "en")
    let reason = try #require(panel.unavailableOptions["engine"]?["graxpert"])
    var resolved = reason
    resolved.locale = english
    #expect(
      String(localized: resolved) == "GraXpert is not installed at /Applications/GraXpert.app.")
    #expect(panel.unavailableOptions["engine"]?["siril-rbf"] == nil)
    #expect(panel.params.choice("engine") == "graxpert", "the user's choice is kept")
    #expect(workspace.missingTool?.tool == .graxpert)

    #expect(await workspace.runTool() == false)
    #expect(calls.engines.isEmpty, "no engine ran, GraXpert's nor another")
    #expect(workspace.studio.steps.count == 1)
    var failure = try #require(workspace.failure)
    failure.locale = english
    #expect(String(localized: failure) == String(localized: resolved))

    // Another engine is the user's own pick: it runs.
    panel.set("engine", .choice("siril-polynomial"))
    #expect(workspace.missingTool == nil)
    #expect(await workspace.runTool())
    #expect(calls.engines == ["siril-polynomial"])
  }

  /// One row: the scope, whether the head is corrected, the bundle layers rewritten.
  struct ScopeCase: Sendable, CustomTestStringConvertible {
    let applyTo: String
    let head: Bool
    let layers: Set<String>
    var testDescription: String { applyTo }
  }

  @Test(
    "testAppliesToChosenLayers", .scratchDirectory,
    arguments: [
      ScopeCase(applyTo: "rgb", head: true, layers: []),
      ScopeCase(applyTo: "lines", head: false, layers: ["Ha", "OIII"]),
      ScopeCase(applyTo: "all", head: true, layers: ["Ha", "OIII", "RGB"]),
    ])
  func testAppliesToChosenLayers(row: ScopeCase) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened)
    let before = workspace.studio.head.planes
    let bundle = Self.bundle()
    workspace.choose(BackgroundExtractionProcess.id)
    try #require(workspace.panel).set("applyTo", .choice(row.applyTo))
    #expect(await workspace.runTool())

    #expect((workspace.studio.head.planes != before) == row.head)
    let context = try workspace.studio.session.history.context(over: bundle.layers)
    for (id, layer) in bundle.layers {
      let rewritten = context[id]?.planes != layer.planes
      #expect(rewritten == row.layers.contains(id), "\(row.applyTo): \(id)")
    }
  }
}
