import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Card 0091's manual walk on run #78's recorded crop: StarNet as this Mac has it (an Intel
/// StarNet2 without Rosetta shows its install card, a runnable one adds the step), then the full
/// deliverable set from the crop's recorded StarNet output, the pane rendered in French and
/// English (PNG attachments, the PR's screenshots). Skips without the finish fixtures.
@MainActor
@Suite(
  "Live Export on run #78's crop — StarNet as installed, the full set from its starless",
  .finishOracle, .tags(.live), .serialized, .timeLimit(.minutes(5)),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct LiveExportRun78Tests {
  static func render(_ model: ExportStageModel, _ name: String) throws {
    for language in ["fr", "en"] {
      let host = NSHostingView(
        rootView: ExportStageView(model: model)
          .environment(\.locale, Locale(identifier: language))
          .frame(width: 1100, height: 760)
          .background(Color(nsColor: .windowBackgroundColor)))
      host.appearance = NSAppearance(named: .darkAqua)
      host.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      Attachment.record(png, named: "export-run78-\(name)-\(language).png")
    }
  }

  /// A project whose Studio holds run #78's crop (`haplus_final`) and the stage over it.
  static func stage(tools: HostTools) throws -> (ProjectPackage, ExportStageModel) {
    let root = try #require(FinishOracle.root)
    let final = try ImageImport.read(at: root.appendingPathComponent("crop/haplus_final.png"))
    let package = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    let stack = try package.store.addStack(
      bundlePath: "stacks/78", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB"])
    let stats = StudioSession.stats(of: final)
    let studio = try StudioModel(
      store: package.store, stackID: stack.id, packageFolder: package.url,
      stackFolder: package.url.appendingPathComponent("stacks/78"),
      bundle: PipelineBundle(stats: stats, layers: ["RGB": final], layerStats: ["RGB": stats]))
    let services = ExportServices(
      tools: tools, scratch: try ScratchDirectory.url.appendingPathComponent("work"))
    let model = ExportStageModel(
      studio: studio, stack: stack, store: package.store, packageFolder: { package.url },
      services: services)
    return (package, model)
  }

  @Test(
    "StarNet as installed: an install card on an Intel build without Rosetta", .scratchDirectory)
  func testStarNetAsInstalled() async throws {
    let (package, model) = try Self.stage(tools: HostTools.live())
    defer { try? package.close() }

    await model.separateStars()

    if let card = model.installCard {
      #expect(card.state == .missing && model.installReason != nil)
      #expect(model.studio.steps.map(\.processID) == ["channel-combination"])
    } else {
      #expect(model.failure == nil)
      #expect(model.studio.steps.last?.processID == StarSeparation.id && model.hasStarless)
    }
    try Self.render(model, "1-starnet-as-installed")
  }

  @Test("the full set from the crop's recorded StarNet output, recorded", .scratchDirectory)
  func testFullSetFromRecordedStarless() async throws {
    let root = try #require(FinishOracle.root)
    let (package, model) = try Self.stage(tools: HostTools { _ in .missing(path: "/none") })
    defer { try? package.close() }
    let studio = model.studio
    let starless = try ImageImport.read(at: root.appendingPathComponent("crop/starless.png"))
      .inRowOrder(studio.head.metadata.rowOrder)
    try studio.apply(
      StarSeparation.id, params: ParamSet(schema: StarSeparation.schema), result: studio.head,
      outputs: [
        .starless: AstroImage(
          width: starless.width, height: starless.height, planes: starless.planes,
          metadata: studio.head.metadata)
      ])
    // The stage reads the step the Studio recorded.
    let stage = ExportStageModel(
      studio: studio, stack: model.stack, store: package.store, packageFolder: { package.url },
      services: ExportServices(tools: HostTools { _ in .missing(path: "/none") }))
    #expect(stage.hasStarless && stage.unavailableDeliverables.isEmpty)

    await stage.export()

    #expect(stage.failure == nil)
    let names = stage.written.map(\.lastPathComponent)
    #expect(names == ExportSettings.Deliverable.allCases.map { $0.rawValue + ".png" })
    let sizes = try stage.written.map { url in
      try ImageImport.read(at: url).width
    }
    #expect(sizes.allSatisfy { $0 == studio.head.width })
    #expect(try package.store.exports(stackID: stage.stack.id).first?.files == names)
    let listing = stage.written.map { $0.path }.joined(separator: "\n")
    Attachment.record(Data(listing.utf8), named: "export-run78-files.txt")
    try Self.render(stage, "2-full-set-exported")
  }
}
