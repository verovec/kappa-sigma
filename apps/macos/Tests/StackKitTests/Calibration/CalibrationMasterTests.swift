import StackKit
import Testing

/// Translated from `calib_test.go` (names, notes), `library_test.go` (findExisting), the set half
/// of `night_test.go` and `provenance_test.go` (dropMaster).
@Suite("CalibrationMaster — names, reuse predicate, pool notes")
struct CalibrationMasterTests {
  typealias Fixtures = CalibrationFixtures

  @Test(
    "the legacy name grammar, night suffix included; default recipe adds nothing",
    arguments: [
      (Fixtures.calibrationKey(.flat, filter: "L", exposureMs: 5, gain: 0, offset: 10, tempC: -25), "master_FLAT_L_5ms_g0o10_b1_-25C"),
      (Fixtures.calibrationKey(.flat, filter: "L", exposureMs: 5, gain: 0, offset: 10, tempC: -25, session: "2023-02-27"), "master_FLAT_L_5ms_g0o10_b1_-25C_n2023-02-27"),
      (Fixtures.calibrationKey(.dark, exposureMs: 300_000, gain: 200, offset: 10, tempC: -10), "master_DARK_300000ms_g200o10_b1_-10C"),
      (Fixtures.calibrationKey(.bias, gain: 100, offset: 10), "master_BIAS_g100o10_b1"),
      (Fixtures.calibrationKey(.darkFlat, exposureMs: 2000, gain: 0, offset: 10, tempC: 5), "master_DARKFLAT_2000ms_g0o10_b1_5C"),
    ])
  func testMasterName_make(key: SetKey, expected: String) {
    #expect(MasterName.make(key) == expected)
  }

  @Test("a non-default recipe gets a fingerprint suffix, never the shared name")
  func testMasterName_recipe() {
    let key = Fixtures.calibrationKey(.dark, exposureMs: 300_000, gain: 200, offset: 10, tempC: -10)
    #expect(MasterName.make(key, recipe: "a1b2c3") == "master_DARK_300000ms_g200o10_b1_-10C_sa1b2c3")
  }

  @Test(
    "a library file name parses back to its master",
    arguments: [
      "master_BIAS_g0o50_b1", "master_DARK_120000ms_g0o50_b1_-10C",
      "master_FLAT_15000ms_g0o50_b1_-5C_n2026-08-30", "master_FLAT_Ha_200ms_g300o10_b2_0C",
      "master_DARKFLAT_2000ms_g0o10_b1_5C_sabc123", "master_FLAT_OIII_5ms_g0o10_b1_-25C_n2023-02-27",
    ])
  func testMasterName_roundTrip(name: String) throws {
    let master = try #require(MasterName.parse("/lib/\(name).fits"))
    #expect(master.path == "/lib/\(name).fits")
    let key = SetKey(
      type: master.type.frameType, filter: master.filter, exposureMs: master.exposureMs,
      gain: master.gain, offset: master.offset, tempBucketC: master.tempMilliC / 1000, bin: master.bin,
      session: master.session)
    #expect(MasterName.make(key, recipe: master.recipe) == name)
  }

  @Test(
    "names that are not masters are not parsed",
    arguments: ["master_DARK_120000ms_g0o50_b1_-10C_defects.lst", "light_0001.fits", "master_FOO_g1o1_b1.fits"])
  func testMasterName_rejects(name: String) {
    #expect(MasterName.parse("/lib/\(name)") == nil)
  }

  @Test(
    "a library master satisfies a calibration set on type, camera, filter, exposure and ±5 °C",
    arguments: [
      (Fixtures.calibrationKey(.dark, exposureMs: 120_000, tempC: -15), "dark.fits"),
      (Fixtures.calibrationKey(.dark, exposureMs: 120_000, tempC: -18), "dark.fits"),
      (Fixtures.calibrationKey(.dark, exposureMs: 120_000, tempC: -25), ""),
      (Fixtures.calibrationKey(.dark, exposureMs: 300_000, tempC: -15), ""),
      (Fixtures.calibrationKey(.bias), "bias.fits"),
      (Fixtures.calibrationKey(.bias, gain: 200), ""),
      (Fixtures.calibrationKey(.flat, filter: "L", exposureMs: 2000, tempC: -15), "flatL.fits"),
      (Fixtures.calibrationKey(.flat, filter: "R", exposureMs: 2000, tempC: -15), ""),
    ])
  func testCalibrationMaster_findExisting(key: SetKey, expected: String) {
    let found = Fixtures.library.first { $0.satisfies(key) }
    #expect((found?.path ?? "") == expected)
  }

  @Test("a per-night flat set is satisfied only by its own night's master")
  func testCalibrationMaster_nightStamped() {
    let key = Fixtures.calibrationKey(.flat, filter: "L", exposureMs: 5, gain: 0, offset: 10, session: "2023-02-27")
    var library = Fixtures.master(.flat, path: "lib", filter: "L", exposureMs: 5, gain: 0, offset: 10)
    #expect(!library.satisfies(key))
    library.session = "2023-02-27"
    #expect(library.satisfies(key))
    library.session = "2023-03-15"
    #expect(!library.satisfies(key))
    library.session = ""
    var keyless = key
    keyless.session = ""
    #expect(library.satisfies(keyless))
  }

  @Test(
    "a lone frame is promoted with a note; a flat adds the missing flat-bias caveat",
    arguments: [
      (MasterType.dark, "master m_x: single-frame pool — the lone frame was promoted unstacked (no outlier rejection)"),
      (.flat, "master m_x: single-frame pool — the lone frame was promoted unstacked (no outlier rejection, no flat-bias calibration)"),
    ])
  func testMasterNotes_lonePromotion(type: MasterType, expected: String) {
    #expect(MasterNotes.lonePromotion("m_x", type: type) == expected)
  }

  @Test(
    "two darks cannot reject outliers: warned for darks and dark-flats only",
    arguments: [
      (MasterType.dark, 2, true), (.darkFlat, 2, true), (.dark, 3, false), (.bias, 2, false),
      (.flat, 2, false), (.dark, 1, false),
    ])
  func testMasterNotes_thinDarkPool(type: MasterType, frames: Int, warns: Bool) {
    let note = MasterNotes.thinDarkPool("m_x", type: type, frames: frames)
    #expect((note != nil) == warns)
    if let note {
      #expect(note.contains("2-frame pool") && note.contains("m_x"))
    }
  }
}
