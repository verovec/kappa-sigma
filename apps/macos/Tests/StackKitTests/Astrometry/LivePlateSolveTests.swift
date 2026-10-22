import Foundation
import ImageKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0093 for real: Siril 1.4 solves run #78's crop (M 31, 250 mm, 3.76 µm) against the
/// local Gaia catalogue of the astro library, on the app's own settings file (never the user's,
/// which other live suites' Siril runs rewrite meanwhile: only what Siril read is checked).
@Suite(
  "Live plate solve — run #78's crop with the local Gaia catalogue", .liveFixtures, .tags(.live),
  .serialized, .timeLimit(.minutes(5)))
struct LivePlateSolveTests {
  static let catalogues = URL.homeDirectory.appendingPathComponent(
    "Documents/astro/library/catalogues")
  static let ready =
    FileManager.default.isExecutableFile(atPath: SirilTool.path())
    && FileManager.default.fileExists(
      atPath: catalogues.appendingPathComponent("siril_cat_healpix8_astro.dat").path)

  /// M 31's nucleus (SIMBAD, J2000): 00 42 44.33 +41 16 07.5.
  static let m31 = (ra: (42 / 60.0 + 44.33 / 3600) * 15, dec: 41 + 16 / 60.0 + 7.5 / 3600)

  /// Angular distance in arcminutes.
  static func arcmin(_ one: (Double, Double), _ two: (Double, Double)) -> Double {
    let radians = Double.pi / 180
    let cosine =
      sin(one.1 * radians) * sin(two.1 * radians)
      + cos(one.1 * radians) * cos(two.1 * radians) * cos((one.0 - two.0) * radians)
    return acos(min(1, cosine)) / radians * 60
  }

  @Test(
    "testSolvesRun78: centre within 1′ of M 31, 3.12″/px, on the app's Siril settings",
    .finishOracle, .scratchDirectory,
    .enabled(if: ready, "Siril or the local Gaia catalogue absent"))
  func testSolvesRun78() async throws {
    let root = try #require(FinishOracle.root)
    let image = try FITSFile.read(at: root.appendingPathComponent("crop/rgb_base.fits")).image()
    let scratch = try ScratchDirectory.url
    let lines = Mutex<[String]>([])
    let solver = PlateSolver.live(
      binary: try SirilTool.locate(), support: scratch.appendingPathComponent("Support"),
      catalogues: Self.catalogues)
    let request = PlateSolveRequest(
      raDegrees: Self.m31.ra, decDegrees: Self.m31.dec, focalMm: 250, pixelSizeUm: 3.76,
      limitMag: nil, catalogue: .localGaia)

    let started = ContinuousClock.now
    let solved = try await solver.solve(image, request: request, scratch: scratch) { progress in
      lines.withLock { $0.append(progress.line) }
    }
    let elapsed = ContinuousClock.now - started

    let solution = solved.solution
    let offset = Self.arcmin((solution.centerRA, solution.centerDec), Self.m31)
    Attachment.record(
      "wall \(elapsed), centre offset \(offset)′, \(solution)", named: "plate-solve-run78.txt")
    #expect(offset < 1, "solved centre \(offset)′ from M 31")
    #expect(abs(solution.scaleArcsecPerPx - 3.117) < 0.01)
    #expect(solution.catalogue?.contains("Gaia") == true, "the local Gaia catalogue, not online")
    let centre = solved.wcs.sky(x: Double(image.width) / 2 - 0.5, y: Double(image.height) / 2 - 0.5)
    #expect(Self.arcmin(centre, (solution.centerRA, solution.centerDec)) < 0.1)
    #expect(
      lines.withLock { $0 }.contains("Reading configuration file \(solver.configFile.path)"),
      "Siril read the app's settings, not the user's")
  }
}
