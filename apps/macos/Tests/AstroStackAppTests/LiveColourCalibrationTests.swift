import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0094 for real: run #78's crop solved (0093), then Siril 1.4 SPCC with the recorded
/// names (IMX571, UV/IR Block — chosen, no default since card 0140 — and the default Average
/// Spiral Galaxy) on the local Gaia spectra; and every name the panel offers is one the
/// installed Siril lists.
@Suite(
  "Live colour calibration — SPCC on run #78's crop, Siril's names", .liveFixtures, .tags(.live),
  .serialized, .timeLimit(.minutes(5)))
struct LiveColourCalibrationTests {
  static let catalogues = URL.homeDirectory.appendingPathComponent(
    "Documents/astro/library/catalogues")
  static let ready =
    FileManager.default.isExecutableFile(atPath: SirilTool.path())
    && FileManager.default.fileExists(
      atPath: catalogues.appendingPathComponent("siril_cat1_healpix8_xpsamp_0.dat").path)

  @Test(
    "testSPCCOnRun78: the factors Siril recorded on 2026-10-22, within 0.005",
    .finishOracle, .scratchDirectory, .enabled(if: ready, "Siril or the local Gaia spectra absent"))
  func testSPCCOnRun78() async throws {
    let root = try #require(FinishOracle.root)
    let scratch = try ScratchDirectory.url
    let support = scratch.appendingPathComponent("Support")
    let binary = try SirilTool.locate()
    let solver = PlateSolver.live(binary: binary, support: support, catalogues: Self.catalogues)
    let solved = try await solver.solve(
      try FITSFile.read(at: root.appendingPathComponent("crop/rgb_base.fits")).image(),
      request: PlateSolveRequest(
        raDegrees: 10.68333, decDegrees: 41.26917, focalMm: 250, pixelSizeUm: 3.76,
        limitMag: nil, catalogue: .localGaia),
      scratch: scratch
    ) { _ in }
    let image = try FITSFile.read(at: root.appendingPathComponent("crop/rgb_base.fits")).image()
    image.metadata.wcs = solved.wcs
    let calibrator = ColourCalibrator.live(
      binary: binary, support: support, catalogues: Self.catalogues)
    var params = ParamSet(schema: ColourCalibrationProcess.schema)
    try params.set("sensor", .choice("Sony IMX571"))
    try params.set("filter", .choice("UV/IR Block"))
    let started = ContinuousClock.now
    let calibrated = try await calibrator.calibrate(
      image, request: ColourCalibrationTool.request(params), scratch: scratch
    ) { _ in }
    let elapsed = ContinuousClock.now - started
    let report = calibrated.report
    Attachment.record("wall \(elapsed), \(report)", named: "spcc-run78.txt")
    for (factor, recorded) in zip(report.factors, [0.758, 0.929, 1.0]) {
      #expect(abs(factor - recorded) <= 0.005, "\(report.factors)")
    }
    #expect((report.stars ?? 0) > 200)
    #expect(calibrated.image.metadata.wcs == solved.wcs)
  }

  @Test(
    "every sensor, filter and white reference the panel offers is in Siril's spcc_list",
    .scratchDirectory, .enabled(if: ready, "Siril absent"))
  func testNamesAreSiril() async throws {
    let lines = Mutex<[String]>([])
    _ = try await SirilRunner.live(binary: try SirilTool.locate()).run(
      SirilScript(
        [
          "oscsensor", "oscfilter", "whiteref", "monosensor", "redfilter", "greenfilter",
          "bluefilter",
        ]
        .map(SirilCommand.spccList)),
      try ScratchDirectory.url
    ) { line in lines.withLock { $0.append(line.text) } }
    let lists = ColourCalibrator.lists(lines.withLock { $0 })
    #expect(Set(SPCCNames.sensors).subtracting(lists["oscsensor"] ?? []).isEmpty)
    #expect(Set(SPCCNames.filters).subtracting(lists["oscfilter"] ?? []).isEmpty)
    #expect(Set(SPCCNames.whiteReferences).subtracting(lists["whiteref"] ?? []).isEmpty)
    // Card 0140: the mono lists equal the recorded ones.
    #expect(lists["monosensor"] == SPCCNames.monoSensors)
    #expect(lists["redfilter"] == SPCCNames.redFilters)
    #expect(lists["greenfilter"] == SPCCNames.greenFilters)
    #expect(lists["bluefilter"] == SPCCNames.blueFilters)
  }
}
