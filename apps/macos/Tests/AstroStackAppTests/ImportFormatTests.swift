import AstroStackApp
import Foundation
import StackKit
import Testing

/// The text the Import sheet writes for the plan's values.
@Suite("ImportFormat — exposures, temperatures, sensors, nights, calibration cells")
struct ImportFormatTests {
  static let english = AstroFormat(locale: Locale(identifier: "en_US"))

  @Test(
    "exposures read in seconds or milliseconds",
    arguments: zip([0, 5, 1000, 2500, 300_000], ["—", "5 ms", "1 s", "2.5 s", "300 s"]))
  func testExposure(ms: Int, text: String) {
    #expect(Self.english.exposure(ms: ms).replacing("\u{a0}", with: " ") == text)
  }

  @Test(
    "only thermal sets show their temperature cluster",
    arguments: zip(
      [
        SetKey(type: .light, tempBucketC: -17), SetKey(type: .dark, tempBucketC: 3),
        SetKey(type: .darkFlat), SetKey(type: .flat, tempBucketC: -5), SetKey(type: .bias),
      ], ["−17 °C", "3 °C", "0 °C", "—", "—"]))
  func testTemperature(key: SetKey, text: String) {
    #expect(ImportFormat.temperature(key, in: Self.english).replacing("\u{a0}", with: " ") == text)
  }

  @Test("sensor settings and night headings")
  func testSensorAndNight() {
    #expect(
      ImportFormat.sensor(SetKey(type: .light, gain: 100, offset: 50, bin: 1)) == "g100 o50 b1")
    #expect(ImportFormat.night("2026-10-17").text("en") == "Night of 2026-10-17")
    #expect(ImportFormat.night("").text("en") == "Shared calibration and undated frames")
    #expect(ImportFormat.night("2026-10-17").text("fr") == "Nuit du 2026-10-17")
  }

  @Test(
    "every calibration status says what will happen",
    arguments: zip(
      [
        ImportPlan.Status.library(path: "/lib/master_BIAS_g100o50_b1.fits", frames: 50),
        .library(path: "/lib/master_FLAT.fits", frames: 0), .build(frames: 1), .build(frames: 20),
        .excluded(.build(frames: 2)), .missing,
      ],
      [
        "library: master_BIAS_g100o50_b1.fits (50 frames)", "library: master_FLAT.fits",
        "build from 1 frame", "build from 20 frames",
        "excluded (proposed: build from 2 frames)", "missing",
      ]))
  func testStatus(status: ImportPlan.Status, text: String) {
    #expect(ImportFormat.status(status).text("en") == text)
  }

  @Test(
    "the calibration statuses in French, nested sentences and plurals included",
    arguments: zip(
      [
        ImportPlan.Status.library(path: "/lib/master_BIAS_g100o50_b1.fits", frames: 1),
        .build(frames: 1), .build(frames: 20), .excluded(.build(frames: 2)), .missing,
      ],
      [
        "bibliothèque\u{a0}: master_BIAS_g100o50_b1.fits (1 pose)",
        "à construire depuis 1 pose", "à construire depuis 20 poses",
        "exclu (proposé\u{a0}: à construire depuis 2 poses)", "manquant",
      ]))
  func testStatusInFrench(status: ImportPlan.Status, text: String) {
    #expect(ImportFormat.status(status).text("fr") == text)
  }
}
