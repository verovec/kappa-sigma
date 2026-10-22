import Foundation
import ImageKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0093: the plate solve Siril runs for the Studio, replayed from Siril 1.4.4 transcripts
/// recorded on run #78's crop (`Fixtures/platesolve`).
@Suite("PlateSolver: Siril platesolve with the app's own config")
struct PlateSolverTests {
  static let request = PlateSolveRequest(
    raDegrees: 10.68333, decDegrees: 41.26917, focalMm: 250, pixelSizeUm: 3.76, limitMag: nil,
    catalogue: .localGaia)

  /// A runner replaying `transcript`: every line to `onLine`, the solved file written on
  /// success (with a TAN solution), Siril's failure thrown otherwise.
  final class Replay: Sendable {
    let transcript: String
    let succeeds: Bool
    private let scripts = Mutex<[String]>([])

    init(_ name: String, succeeds: Bool) throws {
      let url = try #require(
        Bundle.module.url(
          forResource: name, withExtension: "log", subdirectory: "Fixtures/platesolve"))
      transcript = try String(contentsOf: url, encoding: .utf8)
      self.succeeds = succeeds
    }

    var calls: [String] { scripts.withLock { $0 } }

    var runner: SirilRunner {
      SirilRunner(run: { script, directory, onLine in
        self.scripts.withLock { $0.append(script.render()) }
        for line in self.transcript.split(separator: "\n") {
          onLine(SirilLine(parsing: String(line)))
        }
        guard self.succeeds else {
          throw SirilError.scriptFailed(
            exitCode: 1, hint: SirilOutput.errorHint(log: self.transcript))
        }
        try PlateSolverTests.solvedFile(in: directory)
        return self.transcript
      })
    }
  }

  static func solvedFile(in directory: URL) throws {
    var cards = [
      "CTYPE1": "'RA---TAN'", "CTYPE2": "'DEC--TAN'", "CRPIX1": "2.5", "CRPIX2": "1.5",
      "CRVAL1": "10.7032408167172", "CRVAL2": "41.2714040033193",
      "CD1_1": "0.000173", "CD1_2": "-0.000848", "CD2_1": "0.000848", "CD2_2": "0.000173",
    ]
    cards["PLTSOLVD"] = "T"
    try TestFITS.write("solved.fits", in: directory, width: 4, height: 3, cards: cards)
  }

  static func image() -> AstroImage {
    AstroImage(
      width: 4, height: 3, planes: [(0..<12).map { Float($0) / 12 }],
      metadata: ImageMetadata(rowOrder: .bottomUp))
  }

  @Test(
    "the script, the solution read from Siril's lines, -i in the support folder", .scratchDirectory)
  func testScriptAndSolutionParsing() async throws {
    let replay = try Replay("m31-crop-solved", succeeds: true)
    let support = (try ScratchDirectory.url).appendingPathComponent("Support")
    let catalogues = try Self.catalogues()
    let solver = PlateSolver(siril: replay.runner, support: support, catalogues: catalogues)
    let solved = try await solver.solve(
      Self.image(), request: Self.request,
      scratch: (try ScratchDirectory.url).appendingPathComponent("w")
    ) { _ in }

    #expect(
      replay.calls == [
        "requires 1.2.0\nsetext fits\nset32bits\nload input\n"
          + "platesolve 10.683330,41.269170 -force -focal=250 -pixelsize=3.76 -catalog=localgaia"
          + " -noflip\nsave solved\n"
      ])
    #expect(solver.configFile.path.hasPrefix(support.path + "/"))
    let config = try String(contentsOf: solver.configFile, encoding: .utf8)
    #expect(config.contains("catalogue_gaia_astro=\(catalogues.path)/siril_cat_healpix8_astro.dat"))
    #expect(config.contains("catalogue_gaia_photo=\(catalogues.path)\n"))
    #expect(config.contains("update_default_scale=false"))

    let solution = solved.solution
    #expect(solution.scaleArcsecPerPx == 3.117)
    #expect(solution.rotationDeg == 258.45)
    #expect(solution.focalMm == 248.83)
    #expect(solution.pixelSizeUm == 3.76)
    #expect(solution.fieldOfView == #"53' 11.66" x 39' 53.75""#)
    #expect(solution.catalogue == "Gaia DR3 astrometry")
    #expect(solution.offsetArcmin == 0.91)
    #expect(abs(solution.centerRA - (0 + 42 / 60.0 + 48.778 / 3600) * 15) < 1e-9)
    #expect(abs(solution.centerDec - (41 + 16 / 60.0 + 17.054 / 3600)) < 1e-9)
    #expect(solved.wcs.crval == SIMD2(10.7032408167172, 41.2714040033193))
  }

  @Test(
    "an unsolved field fails with Siril's reason, once, no other settings tried", .scratchDirectory)
  func testFailureSurfacesSirilReason() async throws {
    let replay = try Replay("m31-crop-failed", succeeds: false)
    let solver = PlateSolver(
      siril: replay.runner, support: (try ScratchDirectory.url), catalogues: try Self.catalogues())
    await #expect(
      throws: PlateSolveError.failed(
        reason: "Plate solving failed: The image could not be aligned with the reference stars")
    ) {
      try await solver.solve(
        Self.image(), request: Self.request, scratch: (try ScratchDirectory.url)
      ) { _ in }
    }
    #expect(replay.calls.count == 1)
  }

  @Test(
    "a failure without the solve line keeps the script hint; a success without a file is none",
    .scratchDirectory)
  func testOtherFailures() async throws {
    let scratch = try ScratchDirectory.url
    let hinted = PlateSolver(
      siril: SirilRunner { _, _, _ in
        throw SirilError.scriptFailed(exitCode: 1, hint: "Error in line 5 ('platesolve')")
      }, support: scratch, catalogues: try Self.catalogues())
    await #expect(throws: PlateSolveError.failed(reason: "Error in line 5 ('platesolve')")) {
      try await hinted.solve(Self.image(), request: Self.request, scratch: scratch) { _ in }
    }
    let silent = PlateSolver(
      siril: SirilRunner { _, _, onLine in
        onLine(SirilLine(parsing: "log: Siril solve succeeded."))
        return ""
      }, support: scratch, catalogues: try Self.catalogues())
    await #expect(throws: PlateSolveError.self) {
      try await silent.solve(Self.image(), request: Self.request, scratch: scratch) { _ in }
    }
  }

  @Test("local Gaia without the catalogue on disk: refused before Siril runs", .scratchDirectory)
  func testMissingCatalogueRefused() async throws {
    let replay = try Replay("m31-crop-solved", succeeds: true)
    let missing = (try ScratchDirectory.url).appendingPathComponent("nowhere")
    let solver = PlateSolver(
      siril: replay.runner, support: (try ScratchDirectory.url), catalogues: missing)
    await #expect(
      throws: PlateSolveError.catalogueMissing(
        path: missing.appendingPathComponent("siril_cat_healpix8_astro.dat").path)
    ) {
      try await solver.solve(
        Self.image(), request: Self.request, scratch: (try ScratchDirectory.url)
      ) { _ in }
    }
    #expect(replay.calls.isEmpty)
  }

  @Test(
    "the arguments as Siril reads them",
    arguments: [
      (request, "10.683330,41.269170 -force -focal=250 -pixelsize=3.76 -catalog=localgaia -noflip"),
      (
        PlateSolveRequest(
          raDegrees: 40.5, decDegrees: -5.25, focalMm: 135.5, pixelSizeUm: 4.3, limitMag: 14,
          catalogue: .online),
        "40.500000,-5.250000 -force -focal=135.5 -pixelsize=4.3 -limitmag=14 -catalog=gaia -noflip"
      ),
    ])
  func testArguments(request: PlateSolveRequest, expected: String) {
    #expect(SirilCommand.platesolveForced(request.arguments).line == "platesolve " + expected)
    #expect(SirilCommand.platesolveForced(request.arguments).verb == "platesolve")
  }

  @Test("the live runner passes the init file with -i")
  func testInitFileArgument() {
    let arguments = SirilRunner.scriptArguments(
      directory: URL(fileURLWithPath: "/w"), file: URL(fileURLWithPath: "/w/s.ssf"),
      initFile: URL(fileURLWithPath: "/support/siril.ini"))
    #expect(arguments == ["-i", "/support/siril.ini", "-d", "/w", "-s", "/w/s.ssf"])
  }

  static func catalogues() throws -> URL {
    let folder = (try ScratchDirectory.url).appendingPathComponent("catalogues")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent("siril_cat_healpix8_astro.dat"))
    return folder
  }
}
