import Foundation
import ImageKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// The two tools for real (card 0072): the user's GraXpert on run #78's `rgb_base` crop
/// (`LiveGraXpertTests.testRun78RGBBase`), and the Siril engines on a plane gradient. Each test
/// skips without its tool; the GraXpert one also needs the finish fixtures.
@Suite(
  "Live background extraction — GraXpert on run #78, Siril subsky engines", .liveFixtures,
  .tags(.live), .serialized, .timeLimit(.minutes(20)))
struct LiveBackgroundExtractionTests {
  static let graxpertPresent = FileManager.default.fileExists(
    atPath: HostTools.graxpertDefaultPath)

  @Test(
    "testRun78RGBBase: corrected + model written, progress seen, wall time attached",
    .finishOracle, .scratchDirectory, .enabled(if: graxpertPresent, "GraXpert absent"))
  func testRun78RGBBase() async throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let files = manifest.allFiles.filter { $0.path == "crop/rgb_base.fits" }
    try #require(files.count == 1 && FinishOracle.verify(files, root: root) == [])
    let base = root.appendingPathComponent("crop/rgb_base.fits")
    let image = try FITSFile.read(at: base).image()
    let (width, height, rowOrder) = (image.width, image.height, image.metadata.rowOrder)
    let scratch = try ScratchDirectory.url
    let progress = Mutex<[ToolProgress]>([])
    let extraction = BackgroundExtraction.located(
      by: HostTools.live(), siril: SirilRunner { _, _, _ in "" })

    let started = ContinuousClock.now
    let result = try await extraction.run(
      image: image, engine: .graxpert(smoothing: 0.5), correction: .subtract, scratch: scratch
    ) { event in progress.withLock { $0.append(event) } }
    let elapsed = ContinuousClock.now - started
    let seen = progress.withLock { $0 }
    Attachment.record(
      "GraXpert background-extraction on crop/rgb_base.fits (\(width)×\(height)×3): "
        + "\(elapsed), \(seen.count) output lines", named: "graxpert-run78-wall-time.txt")

    #expect(!result.reused && !seen.isEmpty)
    #expect(result.corrected.width == width && result.corrected.height == height)
    #expect(result.model.planes.count == 3 && result.corrected.metadata.rowOrder == rowOrder)
    // A model was taken out: it is not zero, and the corrected sky keeps its level.
    let modelSpread = result.model.planes.map { ($0.max() ?? 0) - ($0.min() ?? 0) }
    #expect(modelSpread.allSatisfy { $0 > 0 })
    let cache = BackgroundCache(root: scratch.appendingPathComponent("background"))
    let key = try cache.key(
      image: try FITSFile.read(at: base).image(), engine: .graxpert(smoothing: 0.5),
      correction: .subtract)
    #expect(
      FileManager.default.fileExists(
        atPath: cache.folder(key).appendingPathComponent("model.fits").path))

    // The same request is served from the cache, without GraXpert.
    let again = try await extraction.run(
      image: try FITSFile.read(at: base).image(), engine: .graxpert(smoothing: 0.5),
      correction: .subtract, scratch: scratch
    ) { _ in }
    #expect(again.reused && again.corrected.planes == result.corrected.planes)
  }

  /// Siril 1.4.4 on a 512 × 384 plane gradient: `subsky 1` is exact; `subsky -rbf` (smooth 0.5,
  /// 30 samples) leaves 2.8 % of the gradient's spread (measured 2026-10-22) — pinned at 5 %.
  @Test(
    "the Siril engines flatten a plane gradient (polynomial exact, RBF within 5 % of it)",
    .scratchDirectory, .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
    arguments: [
      (
        BackgroundEngine.sirilPolynomial(degree: 1), Float(0.01) * BackgroundFlatSkyTests.flat,
        Float(0)
      ),
      (.sirilRBF(smooth: 0.5, samples: 30, tolerance: 1.5, dither: false), Float(0), Float(0.05)),
    ])
  func testSirilEnginesFlattenAPlane(
    engine: BackgroundEngine, absolute: Float, ofGradient: Float
  ) async throws {
    let extraction = BackgroundExtraction(
      graxpert: { throw GraXpertError.missing(path: "unused") },
      siril: SirilRunner.live(binary: try SirilTool.locate()))
    let input = BackgroundFlatSkyTests.gradient(width: 512, height: 384)
    let gradientSpreads = input.planes.map { ($0.max() ?? 0) - ($0.min() ?? 0) }
    let (width, planeCount) = (input.width, input.planes.count)
    let result = try await extraction.run(
      image: input, engine: engine, correction: .subtract, scratch: try ScratchDirectory.url
    ) { _ in }
    #expect(result.corrected.width == width && result.model.planes.count == planeCount)
    for (channel, plane) in result.corrected.planes.enumerated() {
      let spread = (plane.max() ?? 0) - (plane.min() ?? 0)
      let allowed = absolute + ofGradient * gradientSpreads[channel]
      #expect(
        spread <= allowed,
        "\(engine) channel \(channel): residual spread \(spread) of \(gradientSpreads[channel])")
    }
  }
}
