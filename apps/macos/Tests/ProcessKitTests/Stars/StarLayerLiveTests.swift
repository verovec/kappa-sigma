import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// The star layer against stardesat's recorded renders of run #78's 0067 crop: the same
/// `haplus_full` and StarNet `starless` in, every hash checked first.
@Suite(
  "Live star layer — stardesat k 0.25 at r 1 / 0.75 / 0.5 / 0.25 on run #78", .finishOracle,
  .tags(.live), .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized,
  .timeLimit(.minutes(2)))
struct StarLayerLiveTests {
  @Test(
    "within the manifest's tolerance of each recorded stage", .scratchDirectory,
    arguments: ["haplus_final", "stars_75", "stars_50", "stars_25"])
  func testParityStardesat(stage name: String) throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let stage = try #require(manifest.stages.first { $0.name == name })
    let (chroma, presence) = (
      try #require(Double(stage.flags[0])), try #require(Double(stage.flags[1]))
    )
    let paths = ["crop/haplus_full.png", "crop/starless.png", "crop/\(name).png"]
    let files = manifest.allFiles.filter { paths.contains($0.path) }
    try #require(files.count == 3 && FinishOracle.verify(files, root: root) == [])
    let original = try ImageImport.read(at: root.appendingPathComponent(paths[0]))
    let starless = try ImageImport.read(at: root.appendingPathComponent(paths[1]))

    let device = try #require(MTLCreateSystemDefaultDevice())
    var params = ParamSet(schema: StarRecompositionProcess.schema)
    try params.set("chroma", .number(chroma))
    try params.set("presence", .number(presence))
    let size = (original.width, original.height)
    let ours = try ProcessRunner(device: device).run(
      StarRecompositionProcess(params: params, device: device),
      input: GPUImage(device: device, width: size.0, height: size.1, planes: original.planes),
      stats: LayerStats(channels: []),
      layers: [
        "starless": GPUImage(device: device, width: size.0, height: size.1, planes: starless.planes)
      ]
    ).read()

    let rendered = try ScratchDirectory.url.appendingPathComponent("\(name).png")
    try ImageExport.write(
      AstroImage(width: size.0, height: size.1, planes: ours, metadata: original.metadata),
      to: rendered, format: .png16)
    let delta = try FinishImages.difference(rendered, root.appendingPathComponent(paths[2]))
    let report = "mean |Δ| \(delta.meanAbs * 255)/255, max \(delta.maxAbs * 255)/255"
    #expect(delta.meanAbs <= manifest.tolerance.meanAbs, "\(report)")
    #expect(delta.maxAbs <= manifest.tolerance.maxAbs, "\(report)")
  }
}
