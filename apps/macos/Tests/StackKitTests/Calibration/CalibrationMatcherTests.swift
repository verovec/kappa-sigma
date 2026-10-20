import StackKit
import Testing

/// Translated from `internal/calib/match_test.go` and the matcher half of `night_test.go`.
@Suite("CalibrationMatcher — dark, flat and bias for a light set")
struct CalibrationMatcherTests {
  typealias Fixtures = CalibrationFixtures
  static func match(_ light: SetKey, _ masters: [CalibrationMaster], force: Bool = false)
    -> CalibrationSelection
  {
    CalibrationMatcher.match(LightRef(key: light), masters: masters, force: force)
  }

  @Test("an exact match picks the 120 s dark, the L flat and the bias, silently")
  func testMatcher_fullMatch() {
    let selection = Self.match(Fixtures.light("L", exposureMs: 120_000, tempC: -15), Fixtures.standard)
    #expect(selection.dark?.path == "dark120.fits")
    #expect(selection.flat?.path == "flatL.fits")
    #expect(selection.bias?.path == "bias.fits")
    #expect(selection.notes.isEmpty)
  }

  @Test("the exposure-matched dark wins; a missing filter falls back to another filter's flat")
  func testMatcher_exposureMatchedDark() {
    let selection = Self.match(Fixtures.light("Ha", exposureMs: 300_000, tempC: -15), Fixtures.standard)
    #expect(selection.dark?.path == "dark300.fits")
    #expect(selection.flat?.path == "flatL.fits")
    #expect(!selection.notes.isEmpty)
  }

  @Test("a single flat set de-dusts every channel; an exact-filter flat still wins")
  func testMatcher_crossFilterFlat() {
    let ha = Fixtures.master(.flat, path: "flatHa.fits", filter: "Ha", exposureMs: 1000, frames: 100)
    let light = Fixtures.light("L", exposureMs: 120_000, tempC: -15)
    let fallback = Self.match(light, [ha])
    #expect(fallback.flat?.path == "flatHa.fits")
    #expect(Fixtures.notes(fallback, contain: "using the Ha flat"))
    let exact = Self.match(light, [ha, Fixtures.master(.flat, path: "flatL.fits", filter: "L", frames: 50)])
    #expect(exact.flat?.path == "flatL.fits")
    #expect(!Fixtures.notes(exact, contain: "using the"))
  }

  @Test("no flat at all skips flat correction with a clear note")
  func testMatcher_noFlat() {
    let selection = Self.match(
      Fixtures.light("L", exposureMs: 120_000, tempC: -15), [Fixtures.master(.bias, path: "bias.fits", frames: 8)])
    #expect(selection.flat == nil)
    #expect(selection.notes.contains("no flat available — flat correction skipped"))
  }

  @Test("darks match within ±5 °C only", arguments: [(-18, true), (-25, false)])
  func testMatcher_temperatureTolerance(tempC: Int, matches: Bool) {
    let selection = Self.match(Fixtures.light("L", exposureMs: 120_000, tempC: tempC), Fixtures.standard)
    #expect((selection.dark != nil) == matches)
  }

  @Test("another gain is another camera: no dark, no bias")
  func testMatcher_noCameraMatch() {
    let selection = Self.match(Fixtures.light("L", exposureMs: 120_000, gain: 200, tempC: -15), Fixtures.standard)
    #expect(selection.dark == nil)
    #expect(selection.bias == nil)
  }

  @Test("no 60 s dark: the longest same-camera dark is dark-optimized against the bias")
  func testMatcher_darkOptimize() {
    let selection = Self.match(Fixtures.light("L", exposureMs: 60000, tempC: -15), Fixtures.standard)
    #expect(selection.dark?.path == "dark300.fits")
    #expect(selection.darkOptimize)
    #expect(Fixtures.notes(selection, contain: "dark-optimized"))
  }

  static let lone300 = [Fixtures.master(.dark, path: "dark300.fits", exposureMs: 300_000, tempC: -15, frames: 5)]

  @Test("without a bias a different-exposure dark is never applied")
  func testMatcher_noOptimizeWithoutBias() {
    let selection = Self.match(Fixtures.light("L", exposureMs: 60000, tempC: -15), Self.lone300)
    #expect(selection.dark == nil)
    #expect(!selection.darkOptimize)
    #expect(Fixtures.notes(selection, contain: "no matching dark"))
  }

  @Test("forced: a wrong-gain dark and bias are applied, with the mismatch named")
  func testMatcher_forcedCrossGain() {
    let light = Fixtures.light("L", exposureMs: 120_000, gain: 200, tempC: -15)
    let strict = Self.match(light, Fixtures.standard)
    #expect(strict.dark == nil)
    #expect(strict.bias == nil)
    let forced = Self.match(light, Fixtures.standard, force: true)
    #expect(forced.dark?.path == "dark120.fits")
    #expect(!forced.darkOptimize)
    #expect(forced.bias != nil)
    #expect(Fixtures.notes(forced, contain: "forced dark — applied despite mismatched"))
  }

  @Test("forced: an out-of-tolerance dark is applied with the temperature named")
  func testMatcher_forcedOutOfTemperature() {
    let light = Fixtures.light("L", exposureMs: 120_000, tempC: -25)
    #expect(Self.match(light, Fixtures.standard).dark == nil)
    let forced = Self.match(light, Fixtures.standard, force: true)
    #expect(forced.dark?.path == "dark120.fits")
    #expect(Fixtures.notes(forced, contain: "°C"))
  }

  @Test("forced without a bias: the closest dark is subtracted directly, flagged approximate")
  func testMatcher_forcedDirect() {
    let light = Fixtures.light("L", exposureMs: 60000, tempC: -15)
    #expect(Self.match(light, Self.lone300).dark == nil)
    let forced = Self.match(light, Self.lone300, force: true)
    #expect(forced.dark?.path == "dark300.fits")
    #expect(!forced.darkOptimize)
    #expect(Fixtures.notes(forced, contain: "without scaling"))
  }

  @Test("gain 0 / offset 0 lunar keys still match fully; the per-filter flat wins")
  func testMatcher_planetaryKeys() {
    let lunar = [
      Fixtures.master(.bias, path: "bias.fits", gain: 0, offset: 0, frames: 64),
      Fixtures.master(.dark, path: "dark10.fits", exposureMs: 10, gain: 0, offset: 0, tempC: -17, frames: 64),
      Fixtures.master(.flat, path: "flatL.fits", filter: "L", exposureMs: 10, gain: 0, offset: 0, frames: 64),
      Fixtures.master(.flat, path: "flatHa.fits", filter: "Ha", exposureMs: 10, gain: 0, offset: 0, frames: 64),
    ]
    let selection = Self.match(Fixtures.light("L", exposureMs: 10, gain: 0, offset: 0, tempC: -20), lunar)
    #expect(selection.dark?.path == "dark10.fits")
    #expect(!selection.darkOptimize)
    #expect(selection.flat?.path == "flatL.fits")
    #expect(selection.bias?.path == "bias.fits")
  }

  static let multiNightLight = Fixtures.light("L", exposureMs: 120_000, gain: 0, offset: 0, session: "2020-05-06")
  static let far = Fixtures.master(.flat, path: "far.fits", filter: "L", gain: 230, offset: 0, frames: 100, session: "2020-04-15")
  static let near = Fixtures.master(.flat, path: "near.fits", filter: "L", gain: 130, offset: 0, frames: 100, session: "2020-04-26")

  @Test(
    "without its own night's flat, the nearest night wins whatever the order",
    arguments: [[far, near], [near, far]])
  func testMatcher_flatNearestNight(masters: [CalibrationMaster]) {
    #expect(Self.match(Self.multiNightLight, masters).flat?.path == "near.fits")
  }

  @Test("the same night outranks the nearest; an undated flat ranks last but is a last resort")
  func testMatcher_flatNightTiers() {
    let own = Fixtures.master(.flat, path: "own.fits", filter: "L", gain: 99, offset: 0, frames: 3, session: "2020-05-06")
    #expect(Self.match(Self.multiNightLight, [Self.far, Self.near, own]).flat?.path == "own.fits")
    let ghost = Fixtures.master(.flat, path: "ghost.fits", filter: "L", gain: 0, offset: 0, frames: 200)
    #expect(Self.match(Self.multiNightLight, [ghost, Self.far, Self.near]).flat?.path == "near.fits")
    #expect(Self.match(Self.multiNightLight, [ghost]).flat?.path == "ghost.fits")
    var shallow = Self.near
    shallow.frameCount = 10
    shallow.path = "shallow.fits"
    #expect(Self.match(Self.multiNightLight, [shallow, Self.near]).flat?.path == "near.fits")
  }

  @Test("a single-night light keeps the depth ordering among undated flats")
  func testMatcher_singleNightDepth() {
    let flats = [10, 200].map {
      Fixtures.master(.flat, path: "lib_\($0)", filter: "L", exposureMs: 5, gain: 0, offset: 10, frames: $0)
    }
    let light = Fixtures.light("L", exposureMs: 30000, gain: 0, offset: 10)
    #expect(Self.match(light, flats).flat?.frameCount == 200)
  }

  @Test("another night's flat is allowed but named: dust may have moved")
  func testMatcher_crossNightNote() {
    let light = Fixtures.light("L", exposureMs: 30000, gain: 0, offset: 10, session: "2023-02-27")
    let flat = Fixtures.master(.flat, path: "x", filter: "L", exposureMs: 5, gain: 0, offset: 10, frames: 20, session: "2023-03-15")
    let selection = Self.match(light, [flat])
    #expect(selection.flat != nil)
    #expect(selection.notes.contains { $0.contains("2023-03-15") && $0.contains("dust") })
  }

  @Test("library masters are named in a note; a self-calibrating session says nothing")
  func testMatcher_borrowedNote() {
    let borrowed = Fixtures.library.map { master -> CalibrationMaster in
      var master = master
      master.fromLibrary = true
      return master
    }
    let light = Fixtures.light("L", exposureMs: 120_000, tempC: -15)
    #expect(
      Self.match(light, borrowed).notes.contains(
        "from the calibration library, not this session's own frames: dark dark.fits (5 frames) · "
          + "flat flatL.fits (4 frames) · bias bias.fits (8 frames)"))
    #expect(!Self.match(light, Fixtures.library).notes.contains { $0.hasPrefix("from the calibration library") })
  }

  @Test("an excluded role is dropped from the selection, the others untouched")
  func testMatcher_excluded() {
    let light = Fixtures.light("L", exposureMs: 30000, gain: 200, offset: 50, tempC: -10)
    let masters = [
      Fixtures.master(.dark, path: "d", exposureMs: 30000, gain: 200, offset: 50, tempC: -10, frames: 18),
      Fixtures.master(.flat, path: "f", filter: "L", gain: 200, offset: 50, frames: 20),
    ]
    let base = CalibrationMatcher.match(LightRef(key: light), masters: masters)
    #expect(base.dark != nil && base.flat != nil)
    let excluded = CalibrationMatcher.match(
      LightRef(key: light), masters: masters,
      excluded: [CalibrationMatcher.suggestionID(light, role: .dark)])
    #expect(excluded.dark == nil)
    #expect(excluded.flat != nil)
    #expect(excluded.notes.contains("dark excluded — skipped on your request"))
  }

  @Test("a suggestion id is stable per light and role")
  func testMatcher_suggestionID() {
    let light = Fixtures.light("Ha", exposureMs: 30000, gain: 200, offset: 50, tempC: -10)
    #expect(CalibrationMatcher.suggestionID(light, role: .dark) == "dark|Ha|g200o50b1|e30000|t-10")
    #expect(CalibrationMatcher.suggestionID(light, role: .dark) != CalibrationMatcher.suggestionID(light, role: .flat))
  }
}
