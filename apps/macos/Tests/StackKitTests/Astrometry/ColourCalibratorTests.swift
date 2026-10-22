import Foundation
import ImageKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0094: SPCC and PCC as Siril runs them for the Studio, replayed from Siril 1.4.4
/// transcripts recorded on run #78's solved crop (`Fixtures/colourcal`).
@Suite("ColourCalibrator: Siril spcc / pcc, names checked, factors read")
struct ColourCalibratorTests {
  static let spcc = ColourCalibrationRequest(
    method: .spcc(
      sensor: "Sony IMX571", filter: "UV/IR Block", whiteReference: "Average Spiral Galaxy"),
    limitMag: nil, backgroundTolerance: (below: 2.8, above: 2), catalogue: .localGaia)
  static let pcc = ColourCalibrationRequest(
    method: .pcc, limitMag: 14, backgroundTolerance: (below: 3, above: 2.5), catalogue: .online)

  static func transcript(_ name: String) throws -> String {
    let url = try #require(
      Bundle.module.url(
        forResource: "m31-crop-" + name, withExtension: "log", subdirectory: "Fixtures/colourcal"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// A Siril replaying the lists transcript for `spcc_list` scripts and `run` for the other one:
  /// the calibrated file written on success, Siril's failure thrown otherwise.
  final class Replay: Sendable {
    let run: String
    let succeeds: Bool
    private let scripts = Mutex<[String]>([])

    init(_ run: String, succeeds: Bool = true) throws {
      self.run = try ColourCalibratorTests.transcript(run)
      self.succeeds = succeeds
    }

    var calls: [String] { scripts.withLock { $0 } }

    var runner: SirilRunner {
      SirilRunner(run: { script, directory, onLine in
        let text = script.render()
        self.scripts.withLock { $0.append(text) }
        let transcript =
          text.contains("spcc_list") ? try ColourCalibratorTests.transcript("lists") : self.run
        for line in transcript.split(separator: "\n") { onLine(SirilLine(parsing: String(line))) }
        guard text.contains("spcc_list") || self.succeeds else {
          throw SirilError.scriptFailed(exitCode: 1, hint: SirilOutput.errorHint(log: transcript))
        }
        if !text.contains("spcc_list") {
          let input = try FITSFile.read(at: directory.appendingPathComponent("input.fits")).image()
          input.planes = input.planes.map { $0.map { $0 * 0.5 } }
          try FITSFile.create(
            input, keeping: nil, at: directory.appendingPathComponent("calibrated.fits"))
        }
        return transcript
      })
    }
  }

  static func solvedImage() throws -> AstroImage {
    var text =
      [
        "CTYPE1  = 'RA---TAN'", "CTYPE2  = 'DEC--TAN'", "CRPIX1  = 2.5", "CRPIX2  = 1.5",
        "CRVAL1  = 10.7", "CRVAL2  = 41.27", "CD1_1   = -1.7E-04", "CD1_2   = 8.5E-04",
        "CD2_1   = -8.5E-04", "CD2_2   = -1.7E-04",
      ].map { $0.padding(toLength: 80, withPad: " ", startingAt: 0) }.joined() + "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    var metadata = ImageMetadata(rowOrder: .bottomUp)
    metadata.wcs = WCS(header: try FITSFile.parse(Data(text.utf8)).header)
    return AstroImage(
      width: 4, height: 3, planes: (0..<3).map { _ in (0..<12).map { Float($0) / 12 } },
      metadata: metadata)
  }

  static let unsolvedReason: String =
    "This command only works on plate solved images; "
    + "Error in line 5 ('spcc'): command is only for plate solved images."

  static func catalogues() throws -> URL {
    let folder = try ScratchDirectory.url.appendingPathComponent("catalogues")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for file in ["siril_cat_healpix8_astro.dat", "siril_cat1_healpix8_xpsamp_0.dat"] {
      try Data().write(to: folder.appendingPathComponent(file))
    }
    return folder
  }

  static func calibrator(_ replay: Replay) throws -> ColourCalibrator {
    ColourCalibrator(
      siril: replay.runner, support: try ScratchDirectory.url.appendingPathComponent("Support"),
      catalogues: try catalogues())
  }

  @Test(
    "SPCC: names checked, then the exact script; the factors and stars Siril applied",
    .scratchDirectory)
  func testScriptsAndGainParsing() async throws {
    let replay = try Replay("spcc")
    let calibrator = try Self.calibrator(replay)
    let wcs = try Self.solvedImage().metadata.wcs
    let result = try await calibrator.calibrate(
      try Self.solvedImage(), request: Self.spcc, scratch: try ScratchDirectory.url
    ) { _ in }

    #expect(replay.calls.count == 2)
    #expect(
      replay.calls.first?.contains("spcc_list oscsensor\nspcc_list oscfilter\nspcc_list whiteref\n")
        == true)
    let spccLine: String =
      #"spcc "-oscsensor=Sony IMX571" "-oscfilter=UV/IR Block""#
      + #" "-whiteref=Average Spiral Galaxy" -bgtol=2.8,2 -catalog=localgaia"#
    let expected =
      "requires 1.2.0\nsetext fits\nset32bits\nload input\n\(spccLine)\nsave calibrated\n"
    #expect(replay.calls.last == expected)
    let report = result.report
    #expect(report.factors == [0.758, 0.929, 1.0])
    #expect(report.stars == 319)
    #expect(report.background == [3.20423e-03, 9.56828e-04, 5.58095e-05])
    let warning: String =
      "The photometric color calibration seems to have found an imprecise solution,"
      + " consider correcting the image gradient first"
    #expect(report.warnings == [warning])
    #expect(result.image.planes[0][6] == 0.25, "Siril's pixels")
    #expect(result.image.metadata.wcs == wcs && wcs != nil, "the solution kept")
    let config = try String(contentsOf: calibrator.configFile, encoding: .utf8)
    #expect(config.contains("update_default_scale=false"))
  }

  @Test("PCC: its arguments and factors", .scratchDirectory)
  func testPCC() async throws {
    let replay = try Replay("pcc")
    let result = try await Self.calibrator(replay).calibrate(
      try Self.solvedImage(), request: Self.pcc, scratch: try ScratchDirectory.url
    ) { _ in }
    #expect(
      replay.calls == [
        "requires 1.2.0\nsetext fits\nset32bits\nload input\n"
          + "pcc -limitmag=14 -bgtol=3,2.5 -catalog=gaia\nsave calibrated\n"
      ], "no name to check for PCC")
    #expect(result.report.factors == [1.0, 0.957, 0.917])
    #expect(result.report.stars == 587)
  }

  @Test("a failure carries Siril's reason; nothing else is run", .scratchDirectory)
  func testFailure() async throws {
    let replay = try Replay("unsolved", succeeds: false)
    await #expect(
      throws: ColourCalibrationError.failed(reason: Self.unsolvedReason)
    ) {
      _ = try await Self.calibrator(replay).calibrate(
        try Self.solvedImage(), request: Self.spcc, scratch: try ScratchDirectory.url
      ) { _ in }
    }
    #expect(replay.calls.count == 2, "the lists, then SPCC once: no PCC after it")
  }

  @Test(
    "refused before Siril: an unsolved image, a name Siril does not list, a missing catalogue",
    .scratchDirectory)
  func testRefusals() async throws {
    let replay = try Replay("spcc")
    let calibrator = try Self.calibrator(replay)
    let scratch = try ScratchDirectory.url
    await #expect(throws: ColourCalibrationError.unsolved) {
      let bare = AstroImage(
        width: 1, height: 1, planes: [[0], [0], [0]], metadata: ImageMetadata(rowOrder: .bottomUp))
      _ = try await calibrator.calibrate(bare, request: Self.spcc, scratch: scratch) { _ in }
    }
    var unknown = Self.spcc
    unknown.method = .spcc(
      sensor: "Sony IMX999", filter: "UV/IR Block", whiteReference: "Average Spiral Galaxy")
    await #expect(
      throws: ColourCalibrationError.unknownName(kind: .sensor, name: "Sony IMX999")
    ) {
      _ = try await calibrator.calibrate(try Self.solvedImage(), request: unknown, scratch: scratch)
      { _ in }
    }
    #expect(replay.calls.allSatisfy { $0.contains("spcc_list") }, "SPCC never ran")
    let empty = scratch.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let missing = ColourCalibrator(siril: replay.runner, support: scratch, catalogues: empty)
    await #expect(throws: ColourCalibrationError.catalogueMissing(path: empty.path)) {
      _ = try await missing.calibrate(try Self.solvedImage(), request: Self.spcc, scratch: scratch)
      { _ in }
    }
  }

  @Test("Siril's lists, by kind, as spcc_list prints them")
  func testLists() throws {
    let lists = ColourCalibrator.lists(
      try Self.transcript("lists").split(separator: "\n").map {
        SirilLine(parsing: String($0)).text
      })
    #expect(lists["oscsensor"]?.contains("Sony IMX571") == true)
    #expect(lists["oscsensor"]?.count == 47)
    #expect(lists["oscfilter"]?.contains("ZWO Duo-Band") == true)
    #expect(lists["whiteref"]?.first == "Average Spiral Galaxy")
    #expect(lists["oscsensor"]?.contains("OSC Filters") == false)
  }
}

extension ColourCalibratorTests {
  @Test(
    "PCC on the local catalogue needs the astrometric file; a success without a file is none",
    .scratchDirectory)
  func testPCCCatalogueAndNoOutput() async throws {
    let scratch = try ScratchDirectory.url
    let empty = scratch.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    var local = Self.pcc
    local.catalogue = .localGaia
    let missing = ColourCalibrator(
      siril: SirilRunner { _, _, _ in "" }, support: scratch, catalogues: empty)
    await #expect(
      throws: ColourCalibrationError.catalogueMissing(
        path: empty.appendingPathComponent("siril_cat_healpix8_astro.dat").path)
    ) {
      _ = try await missing.calibrate(
        try Self.solvedImage(), request: local, scratch: scratch, onProgress: { _ in })
    }
    let silent = ColourCalibrator(
      siril: SirilRunner { _, _, _ in "" }, support: scratch, catalogues: try Self.catalogues())
    await #expect(throws: ColourCalibrationError.self) {
      _ = try await silent.calibrate(
        try Self.solvedImage(), request: Self.pcc, scratch: scratch, onProgress: { _ in })
    }
  }
}
