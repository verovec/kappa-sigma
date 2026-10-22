import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Background extraction in the Studio (card 0092), over fake engines: Apply runs the chosen
/// engine and records one step with the model as an output, the Model toggle shows it, a
/// missing tool is named and never replaced by another engine (R2).
@MainActor
@Suite(
  "Background extraction in the Studio — step, model view, no fallback, chosen layers",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct BackgroundProcessTests {
  /// The tools the fake engine was asked for, in order.
  final class Calls: Sendable {
    private let storage = Mutex<[String]>([])
    var engines: [String] { storage.withLock { $0 } }
    func record(_ engine: String) { storage.withLock { $0.append(engine) } }
  }

  /// Tools where `missing` is not installed; the engine subtracts 0.01 and models 0.01.
  static func tools(missing: Set<HostTool> = [], calls: Calls = Calls()) -> StudioTools {
    StudioTools(
      locate: { tool in
        missing.contains(tool)
          ? .missing(path: "/Applications/\(tool.productName).app")
          : .found(path: "/usr/local/bin/\(tool.rawValue)", version: nil)
      },
      background: { image, params, progress in
        calls.record(params.choice("engine"))
        progress(1)
        let corrected = AstroImage(
          width: image.width, height: image.height,
          planes: image.planes.map { $0.map { $0 - 0.01 } }, metadata: image.metadata)
        let model = AstroImage(
          width: image.width, height: image.height,
          planes: image.planes.map { $0.map { _ in 0.01 } }, metadata: image.metadata)
        return (corrected, model)
      })
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

  static func workspace(_ opened: StudioModelTests.Opened, tools: StudioTools) throws
    -> StudioWorkspaceModel
  {
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, packageFolder: opened.package.url,
      stackFolder: opened.folder, bundle: bundle())
    return try StudioWorkspaceModel(studio: studio, base: [.color, .emission], tools: tools)
  }

  @Test("testStepOutputsAndModelToggle", .scratchDirectory)
  func testStepOutputsAndModelToggle() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, tools: Self.tools())
    let combined = workspace.studio.head.planes
    #expect(!workspace.canShowModel)

    workspace.choose(BackgroundExtractionProcess.id)
    await workspace.refreshTools()
    #expect(!workspace.isPreviewing, "a batch process has no live preview")
    let panel = try #require(workspace.panel)
    panel.set("applyTo", .choice("all"))
    await workspace.runBatch()
    #expect(workspace.failure == nil)
    #expect(workspace.studio.steps.map(\.processID).last == BackgroundExtractionProcess.id)
    let step = try #require(workspace.studio.steps.last)
    #expect(step.outputs.keys.map(\.self) == [.backgroundModel])
    #expect(step.replaced.keys.sorted() == ["Ha", "OIII", "RGB"])
    #expect(workspace.batchProgress == nil, "the progress row goes when the run ends")
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
    let workspace = try Self.workspace(
      opened, tools: Self.tools(missing: [.graxpert], calls: calls))
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

    await workspace.runBatch()
    #expect(calls.engines.isEmpty, "no engine ran, GraXpert's nor another")
    #expect(workspace.studio.steps.count == 1)
    var failure = try #require(workspace.failure)
    failure.locale = english
    #expect(String(localized: failure) == String(localized: resolved))

    // Another engine is the user's own pick: it runs.
    panel.set("engine", .choice("siril-polynomial"))
    #expect(workspace.missingTool == nil)
    await workspace.runBatch()
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
    let (applyTo, expected) = (row.applyTo, row)
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, tools: Self.tools())
    let before = workspace.studio.head.planes
    let bundle = Self.bundle()
    workspace.choose(BackgroundExtractionProcess.id)
    try #require(workspace.panel).set("applyTo", .choice(applyTo))
    await workspace.runBatch()

    #expect((workspace.studio.head.planes != before) == expected.head)
    let context = try workspace.studio.session.history.context(over: bundle.layers)
    for (id, layer) in bundle.layers {
      let rewritten = context[id]?.planes != layer.planes
      #expect(rewritten == expected.layers.contains(id), "\(applyTo): \(id)")
    }
  }
}
