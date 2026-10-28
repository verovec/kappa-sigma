import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// The card's chain end to end on run #78's 0067 crop, with the user's StarNet2: `haplus_full`
/// → StarNet (progress reported) → the recorded `starless` → the deliverable set at star colour
/// 0.25. Skips without the fixtures or StarNet.
@Suite(
  "Live StarNet chain — run #78 crop → StarNet2 → deliverable set", .finishOracle, .tags(.live),
  .enabled(
    if: FileManager.default.isExecutableFile(atPath: HostTools.starnetDefaultPath),
    "StarNet2 absent"),
  .enabled(
    if: ExecutableCheck.refusal(path: HostTools.starnetDefaultPath) == nil,
    "StarNet2 cannot launch on this Mac (an Intel build without Rosetta)"),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized, .timeLimit(.minutes(10)))
struct LiveStarNetChainTests {
  @Test(
    "StarNet matches the recorded starless; the five deliverables are written", .scratchDirectory)
  func testChain() async throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let paths = ["crop/haplus_full.png", "crop/starless.png"]
    let files = manifest.allFiles.filter { paths.contains($0.path) }
    try #require(files.count == 2 && FinishOracle.verify(files, root: root) == [])
    let original = try ImageImport.read(at: root.appendingPathComponent(paths[0]))
    let scratch = try ScratchDirectory.url

    let progress = Mutex<[Double]>([])
    let runner = try await StarNetRunner.located(by: HostTools.live())
    let starless = try await runner.starless(
      of: ImageImport.read(at: root.appendingPathComponent(paths[0])),
      in: scratch.appendingPathComponent("starnet")
    ) { percent in progress.withLock { $0.append(percent) } }
    let seen = progress.withLock { $0 }
    #expect(seen.count >= 2 && seen == seen.sorted() && seen.last == 100)

    let starlessURL = scratch.appendingPathComponent("starless.png")
    try ImageExport.write(starless, to: starlessURL, format: .png16)
    let delta = try FinishImages.difference(starlessURL, root.appendingPathComponent(paths[1]))
    #expect(
      delta.meanAbs <= manifest.tolerance.meanAbs,
      "mean |Δ| \(delta.meanAbs * 255)/255, max \(delta.maxAbs * 255)/255")

    let device = try #require(MTLCreateSystemDefaultDevice())
    let written = try DeliverableExport(device: device).write(
      original: original, starless: starless, settings: ExportSettings(),
      to: scratch.appendingPathComponent("deliverables"),
      astro: scratch.appendingPathComponent("astro"))
    #expect(
      written.map(\.lastPathComponent) == [
        "final.png", "final-starless.png", "final-75-stars.png", "final-50-stars.png",
        "final-25-stars.png",
      ])
  }
}
