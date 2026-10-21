import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// The Galaxy · OSC profile reproduces the PO's HaPlus deliverable (card 0060): its recipes are
/// the 0051/0067 parity recipes, and its screens step run through `PipelineRunner` on run #78's
/// crop equals astrocomp's `screens_only` render within the manifest's tolerance.
@Suite(
  "Live profiles — the Galaxy · OSC profile reproduces HaPlus on run #78", .finishOracle,
  .tags(.live), .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized,
  .timeLimit(.minutes(2)))
struct ProfileLiveTests {
  static func galaxy() throws -> Profile {
    try #require(
      try ProfileLibrary.builtins(registry: ProcessRegistry.standard())
        .first { $0.id == "galaxy-osc-broadband-dualband" })
  }

  @Test("its recipes are the recorded HaPlus flags: screens, saturation, star colour")
  func testRecipesMatchTheRecordedChain() throws {
    let galaxy = try Self.galaxy()
    let manifest = try FinishOracle.manifest()
    let screens = try #require(galaxy.steps.first { $0.recipe.processID == "emission-screens" })
    let haPlus = try ScreensLiveTests.haPlus()
    #expect(screens.recipe.params == haPlus.entries)
    let full = try #require(manifest.stages.first { $0.name == "haplus_full" })
    let sat = try #require(full.flags.firstIndex(of: "-sat"))
    let saturation = try #require(galaxy.steps.first { $0.recipe.processID == "saturation" })
    #expect(saturation.values["amount"] == .number(try #require(Double(full.flags[sat + 1]))))
    let final = try #require(manifest.stages.first { $0.name == "haplus_final" })
    let stars = try #require(galaxy.steps.first { $0.recipe.processID == "star-recomposition" })
    #expect(stars.values["chroma"] == .number(try #require(Double(final.flags[0]))))
  }

  @Test("its screens step through the pipeline runner equals screens_only", .scratchDirectory)
  func testGalaxyProfileReproducesHaPlus() async throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let paths = ["crop/hdr_only.fits", "crop/syn_Ha.fits", "crop/syn_OIII.fits"]
    let files = manifest.allFiles.filter {
      paths.contains($0.path) || $0.path == "crop/screens_only.png"
    }
    try #require(files.count == 4 && FinishOracle.verify(files, root: root) == [])
    let images = try paths.map { try FITSFile.read(at: root.appendingPathComponent($0)).image() }
    let (width, height) = (images[0].width, images[0].height)
    let (cx, cy) = (Int((Double(width) * 0.005).rounded()), Int((Double(height) * 0.005).rounded()))
    let (xs, ys) = (cx..<(width - cx), cy..<(height - cy))
    let cropped = images.map {
      $0.planes.map { ScreensLiveTests.crop($0, width: width, x: xs, y: ys) }
    }
    let metadata = ImageMetadata(rowOrder: .bottomUp)
    let image = { (planes: [[Float]]) in
      AstroImage(width: xs.count, height: ys.count, planes: planes, metadata: metadata)
    }
    let bundle = PipelineBundle(
      stats: LayerStats(channels: []),
      layers: ["Ha": image(cropped[1]), "OIII": image(cropped[2])],
      layerStats: ["Ha": cropped[1], "OIII": cropped[2]].mapValues {
        LayerStats(channels: $0.map(ScreensLiveTests.medMADN))
      })
    let galaxy = try Self.galaxy()
    let screens = try #require(
      galaxy.pipeline.steps.first { $0.recipe.processID == "emission-screens" })
    var step = screens
    step.mode = .auto
    let runner = try PipelineRunner(
      registry: ProcessRegistry.standard(), device: #require(MTLCreateSystemDefaultDevice()))
    let replay = try await runner.replay(
      Pipeline(name: galaxy.id, steps: [step]),
      on: image(ScreensLiveTests.stretchBase(cropped[0], target: 0.085)),
      in: ScratchDirectory.url.appendingPathComponent("history"), bundle: bundle)
    #expect(replay.outcome == .finished)

    let rendered = try ScratchDirectory.url.appendingPathComponent("profile-screens.png")
    try ImageExport.write(replay.history.current, to: rendered, format: .png16)
    let delta = try FinishImages.difference(
      rendered, root.appendingPathComponent("crop/screens_only.png"))
    let report = "mean |Δ| \(delta.meanAbs * 255)/255, max \(delta.maxAbs * 255)/255"
    #expect(delta.meanAbs <= manifest.tolerance.meanAbs, "\(report)")
    #expect(delta.maxAbs <= manifest.tolerance.maxAbs, "\(report)")
  }
}
