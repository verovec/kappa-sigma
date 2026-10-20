import StackKit
import Testing

/// Translated from `suggest_test.go`, `preview_candidates_test.go` and the preview half of
/// `filterset_masters_test.go`: what a run would apply, per light channel, without stacking.
@Suite("CalibrationPreview — candidates and suggestions per light channel")
struct CalibrationPreviewTests {
  typealias Fixtures = CalibrationFixtures

  static func inventory(_ sets: [FrameSet]) -> Inventory {
    var inventory = Inventory(root: "", frames: [])
    inventory.sets = sets
    return inventory
  }

  static func lightSet(_ filter: String, gain: Int, offset: Int, exposureMs: Int, tempC: Int)
    -> FrameSet
  {
    Fixtures.set(
      SetKey(
        type: .light, filter: filter, exposureMs: exposureMs, gain: gain, offset: offset,
        tempBucketC: tempC, bin: 1),
      count: 10)
  }

  static func calSet(
    _ type: FrameType, filter: String = "", gain: Int, offset: Int, exposureMs: Int = 0,
    tempC: Int = 0,
    count: Int
  ) -> FrameSet {
    var key = SetKey(type: type, gain: gain, offset: offset, bin: 1)
    if type != .bias {
      key.exposureMs = exposureMs
      key.tempBucketC = tempC
    }
    if type == .flat { key.filter = filter }
    return Fixtures.set(key, count: count)
  }

  static let sample = [
    Fixtures.master(
      .dark, path: "/lib/d.fits", exposureMs: 30000, gain: 200, offset: 50, tempC: -10, frames: 18),
    Fixtures.master(.flat, path: "/lib/f.fits", filter: "L", gain: 200, offset: 50, frames: 20),
  ]

  static func roles(_ channel: CalibrationPreview.Channel) -> [CalibrationRole: CalibrationPreview
    .Suggestion]
  {
    Dictionary(channel.suggestions.map { ($0.role, $0) }, uniquingKeysWith: { $1 })
  }

  @Test("each light channel gets its dark and flat; a borrowed filter is explained")
  func testCalibrationPreview_suggest() throws {
    let inventory = Self.inventory([
      Self.lightSet("L", gain: 200, offset: 50, exposureMs: 30000, tempC: -10),
      Self.lightSet("R", gain: 200, offset: 50, exposureMs: 30000, tempC: -10),
    ])
    let preview = CalibrationPreview(inventory: inventory, masters: Self.sample)
    try #require(preview.channels.count == 2)
    let luminance = Self.roles(preview.channels[0])
    #expect(preview.channels[0].filter == "L")
    #expect(luminance[.dark]?.master.frameCount == 18)
    #expect(luminance[.flat] != nil)
    #expect(preview.channels[0].notes.isEmpty)
    #expect(Self.roles(preview.channels[1])[.flat] != nil)
    #expect(!preview.channels[1].notes.isEmpty)
  }

  @Test("forced: a mismatched dark is offered as a suggestion, with the reason")
  func testCalibrationPreview_forced() throws {
    let inventory = Self.inventory([
      Self.lightSet("L", gain: 139, offset: 21, exposureMs: 60000, tempC: -20)
    ])
    let strict = CalibrationPreview(inventory: inventory, masters: Self.sample)
    #expect(Self.roles(try #require(strict.channels.first))[.dark] == nil)
    let forced = try #require(
      CalibrationPreview(inventory: inventory, masters: Self.sample, force: true).channels.first)
    #expect(Self.roles(forced)[.dark]?.master.gain == 200)
    #expect(forced.notes.contains { $0.contains("forced dark") })
  }

  static let ownCalibration = [
    calSet(.bias, gain: 0, offset: 10, count: 400),
    calSet(.dark, gain: 0, offset: 10, exposureMs: 10, tempC: -15, count: 64),
    calSet(.flat, filter: "L", gain: 0, offset: 10, exposureMs: 10, tempC: -15, count: 239),
  ]

  @Test("a capture that calibrates itself beats a stale library master, without gap notes")
  func testCalibrationPreview_ownFrames() throws {
    let inventory = Self.inventory(
      [Self.lightSet("L", gain: 0, offset: 10, exposureMs: 10, tempC: -15)] + Self.ownCalibration)
    let stale = [
      Fixtures.master(.bias, path: "/lib/stale_bias.fits", gain: 300, offset: 50, frames: 400)
    ]
    let candidates = CalibrationPreview.candidates(inventory: inventory, library: stale)
    let channel = try #require(
      CalibrationPreview(inventory: inventory, masters: candidates).channels.first)
    let roles = Self.roles(channel)
    #expect(Set(roles.keys) == [.dark, .flat, .bias])
    #expect(roles.values.allSatisfy { $0.fromCapture })
    #expect(roles[.bias]?.master.gain == 0)
    #expect(channel.notes.isEmpty)
  }

  @Test("a 10 ms capture dark is offered to 20 s lights through bias-scaled -opt")
  func testCalibrationPreview_scalableDark() throws {
    let inventory = Self.inventory([
      Self.lightSet("L", gain: 0, offset: 10, exposureMs: 20000, tempC: -15),
      Self.ownCalibration[0],
      Self.ownCalibration[1],
    ])
    let candidates = CalibrationPreview.candidates(inventory: inventory, library: [])
    let channel = try #require(
      CalibrationPreview(inventory: inventory, masters: candidates).channels.first)
    let dark = try #require(Self.roles(channel)[.dark])
    #expect(dark.fromCapture)
    #expect(dark.master.exposureMs == 10)
    #expect(channel.notes.contains { $0.contains("dark-optimized") })
  }

  @Test("candidates: one path-less synthetic per calibration set a library master does not cover")
  func testCalibrationPreview_candidates() {
    let inventory = Self.inventory(Self.ownCalibration)
    let synthetic = CalibrationPreview.candidates(inventory: inventory, library: [])
    #expect(synthetic.count == 3)
    #expect(synthetic.allSatisfy { $0.path.isEmpty })
    let byType = Dictionary(synthetic.map { ($0.type, $0) }, uniquingKeysWith: { $1 })
    #expect(byType[.bias]?.offset == 10)
    #expect(byType[.bias]?.frameCount == 400)
    #expect(byType[.dark]?.exposureMs == 10)
    #expect(byType[.dark]?.tempMilliC == -15000)
    #expect(byType[.dark]?.hasTemp == true)
    #expect(byType[.flat]?.filter == "L")

    // A field-matching library master without a `.sig` proving these frames is rebuilt by the
    // run, so the preview offers what the run will build (the proven case is
    // `CalibrationReviewTests.testCalibrationPreview_reuseNeedsProof`; Go reused on fields alone).
    let unproven = CalibrationPreview.candidates(
      inventory: inventory,
      library: [
        Fixtures.master(.bias, path: "/lib/master_BIAS.fits", gain: 0, offset: 10, frames: 999)
      ])
    #expect(unproven.count == 4)
    #expect(unproven.filter { $0.type == .bias }.map(\.path) == ["/lib/master_BIAS.fits", ""])

    let stale = CalibrationPreview.candidates(
      inventory: inventory,
      library: [Fixtures.master(.bias, path: "/lib/stale.fits", gain: 300, offset: 50, frames: 400)]
    )
    #expect(stale.count == 4)
  }

  @Test("a synthetic flat carries its night's verdict, so the preview predicts the run")
  func testCalibrationPreview_flatCarriesNightVerdict() {
    let night = CalibrationFilterSetTests.nightA
    let inventory = CalibrationFilterSetTests.scan(
      [(night, .dualband)],
      calibration: [
        CalibrationFilterSetTests.oscCalibration(night, .flat, exposureMs: 2000),
        CalibrationFilterSetTests.oscCalibration(night, .bias),
      ])
    let candidates = CalibrationPreview.candidates(inventory: inventory, library: [])
    #expect(candidates.count == 2)
    #expect(candidates.first { $0.type == .flat }?.filterSet == .dualband)
    #expect(candidates.first { $0.type == .bias }?.filterSet == .unknown)
  }

  @Test("a dual-band night is refused the broadband night's flat, and told why")
  func testCalibrationPreview_crossSetRefused() throws {
    let inventory = CalibrationFilterSetTests.scan(
      [
        (CalibrationFilterSetTests.nightA, .dualband),
        (CalibrationFilterSetTests.nightB, .broadband),
      ],
      calibration: [
        CalibrationFilterSetTests.oscCalibration(
          CalibrationFilterSetTests.nightB, .flat, exposureMs: 2000)
      ])
    let preview = CalibrationPreview(
      inventory: inventory,
      masters: CalibrationPreview.candidates(inventory: inventory, library: []))
    let channel = try #require(
      preview.channels.first { $0.session == CalibrationFilterSetTests.nightA })
    #expect(!channel.suggestions.contains { $0.role == .flat })
    #expect(channel.notes.joined().contains("excluded"))
  }
}
