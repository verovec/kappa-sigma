import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// The screens against astrocomp's `screens_only` render of run #78's 0067 crop (HaPlus flags,
/// `-sat 0` so only the screens differ from the base), every input hash-checked first.
///
/// astrocomp's own steps around the screens are reproduced here in double, from `main.go`: the
/// coverage crop (`-crop 0.005`) and the linked base stretch (`-base-bg 0.085`). The line layers'
/// statistics are its `medMADN` (every third pixel, upper median): what the bundle hands the
/// process in the app.
@Suite(
  "Live screens — astrocomp HaPlus screens_only on run #78", .finishOracle, .tags(.live),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized, .timeLimit(.minutes(2)))
struct ScreensLiveTests {
  static let sigmaK = -2.5

  /// astrocomp `medMADN(p, 3)`.
  static func medMADN(_ plane: [Float]) -> ChannelStats {
    let samples = stride(from: 0, to: plane.count, by: 3).map { Double(plane[$0]) }.sorted()
    let median = samples[samples.count / 2]
    let deviations = samples.map { abs($0 - median) }.sorted()
    return ChannelStats(
      median: median, madn: deviations[deviations.count / 2] * 1.4826,
      minimum: samples.first ?? 0, maximum: samples.last ?? 1)
  }

  /// astrocomp's linked base stretch: shadows and median averaged over the planes.
  static func stretchBase(_ planes: [[Float]], target: Double) -> [[Float]] {
    let stats = planes.map(medMADN)
    let shadows = max(stats.map { $0.median + sigmaK * $0.madn }.reduce(0, +) / 3, 0)
    let median = stats.map(\.median).reduce(0, +) / 3
    let x0 = (median - shadows) / (1 - shadows)
    let midtone = x0 * (1 - target) / (x0 - 2 * target * x0 + target)
    return planes.map { plane in
      plane.map { Float(ScreensOracle.mtf((Double($0) - shadows) / (1 - shadows), midtone)) }
    }
  }

  static func crop(_ plane: [Float], width: Int, x: Range<Int>, y: Range<Int>) -> [Float] {
    y.flatMap { row in plane[(row * width + x.lowerBound)..<(row * width + x.upperBound)] }
  }

  /// The recorded `screens_only` flags, as panel values.
  static func haPlus() throws -> ParamSet {
    var params = ParamSet(schema: EmissionScreensProcess.schema)
    let values: [String: ParamValue] = [
      "haBackground": .number(0.12), "haBlack": .number(0.115), "haOpacity": .number(0.95),
      "oiiiBackground": .number(0.12), "oiiiBlack": .number(0.126), "oiiiOpacity": .number(0.80),
      "oiiiBoost": .number(1.25), "starRadius": .number(4), "smooth": .number(0),
      "shadowsClip": .number(sigmaK), "haTint": .choice("red"), "oiiiTint": .choice("teal"),
    ]
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  @Test("mean |Δ| and max |Δ| within the manifest's tolerance", .scratchDirectory)
  func testParityAstrocompHaPlus() throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let stage = try #require(manifest.stages.first { $0.name == "screens_only" })
    #expect(stage.flags.contains("-sat") && stage.flags.last == "0", "screens isolated")
    let paths = ["crop/hdr_only.fits", "crop/syn_Ha.fits", "crop/syn_OIII.fits"]
    let files = manifest.allFiles.filter {
      paths.contains($0.path) || $0.path == "crop/screens_only.png"
    }
    try #require(files.count == 4 && FinishOracle.verify(files, root: root) == [])
    let images = try paths.map { try FITSFile.read(at: root.appendingPathComponent($0)).image() }
    let (width, height) = (images[0].width, images[0].height)
    let all = images.flatMap(\.planes)
    // The coverage box is the whole crop when every input is positive everywhere.
    try #require((0..<(width * height)).allSatisfy { index in all.allSatisfy { $0[index] > 0 } })
    let (cx, cy) = (Int((Double(width) * 0.005).rounded()), Int((Double(height) * 0.005).rounded()))
    let (xs, ys) = (cx..<(width - cx), cy..<(height - cy))
    let cropped = images.map { $0.planes.map { Self.crop($0, width: width, x: xs, y: ys) } }
    let base = Self.stretchBase(cropped[0], target: 0.085)

    let device = try #require(MTLCreateSystemDefaultDevice())
    let size = (xs.count, ys.count)
    let layers = try ["Ha": cropped[1], "OIII": cropped[2]].mapValues {
      try GPUImage(device: device, width: size.0, height: size.1, planes: $0)
    }
    let layerStats = ["Ha": cropped[1], "OIII": cropped[2]].mapValues {
      LayerStats(channels: $0.map(Self.medMADN))
    }
    let ours = try ProcessRunner(device: device).run(
      EmissionScreensProcess(params: Self.haPlus(), device: device),
      input: GPUImage(device: device, width: size.0, height: size.1, planes: base),
      stats: LayerStats(channels: []), layers: layers, layerStats: layerStats
    ).read()

    let rendered = try ScratchDirectory.url.appendingPathComponent("screens.png")
    // Planes in FITS file order (bottom-up): ImageExport flips them to the PNG's top-down rows.
    try ImageExport.write(
      AstroImage(
        width: size.0, height: size.1, planes: ours, metadata: ImageMetadata(rowOrder: .bottomUp)),
      to: rendered, format: .png16)
    let delta = try FinishImages.difference(
      rendered, root.appendingPathComponent("crop/screens_only.png"))
    let report = "mean |Δ| \(delta.meanAbs * 255)/255, max \(delta.maxAbs * 255)/255"
    #expect(delta.meanAbs <= manifest.tolerance.meanAbs, "\(report)")
    #expect(delta.maxAbs <= manifest.tolerance.maxAbs, "\(report)")
  }
}
