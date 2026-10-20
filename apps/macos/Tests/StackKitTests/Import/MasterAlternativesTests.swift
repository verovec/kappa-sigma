import Foundation
import StackKit
import Testing

/// "Use another…" (card 0071): the library masters a role could take, each with the matcher's
/// own verdict, and the capture set a master is rebuilt from.
@Suite("ImportPlan alternatives — the other masters a role could use, and why")
struct MasterAlternativesTests {
  static let light = CalibrationFixtures.light("L", exposureMs: 300_000, gain: 139, tempC: -15)

  static func plan(_ library: [CalibrationMaster], sets extra: [FrameSet] = []) -> ImportPlan {
    var inventory = Inventory(root: "", frames: [])
    inventory.sets = [CalibrationFixtures.set(light)] + extra
    return ImportPlan(inventory: inventory, library: library, request: ImportRequest(paths: ["/c"]))
  }

  @Test("each library dark is chosen, a match, or usable only when forced")
  func testDarkAlternatives() throws {
    let library = [
      CalibrationFixtures.master(
        .dark, path: "/lib/d300_-15.fits", exposureMs: 300_000, tempC: -15, fromLibrary: true),
      CalibrationFixtures.master(
        .dark, path: "/lib/d300_-12.fits", exposureMs: 300_000, tempC: -12, fromLibrary: true),
      CalibrationFixtures.master(
        .dark, path: "/lib/d300_g0.fits", exposureMs: 300_000, gain: 0, tempC: -15,
        fromLibrary: true),
      CalibrationFixtures.master(.flat, path: "/lib/flatL.fits", filter: "L", fromLibrary: true),
    ]
    let plan = Self.plan(library)
    let channel = try #require(plan.calibration.first)
    let dark = try #require(channel.cells.first)
    #expect(dark.master?.path == "/lib/d300_-15.fits")

    let alternatives = plan.alternatives(for: dark, of: channel)
    #expect(
      alternatives.map(\.master.path) == [
        "/lib/d300_-15.fits", "/lib/d300_-12.fits", "/lib/d300_g0.fits",
      ])
    #expect(alternatives.map(\.verdict) == [.chosen, .matches, .needsForce])
  }

  @Test("the capture set behind a master the run would build is found, for a rebuild")
  func testSourceSet() throws {
    let darkKey = CalibrationFixtures.calibrationKey(
      .dark, exposureMs: 300_000, gain: 139, offset: 21, tempC: -15)
    let plan = Self.plan([], sets: [CalibrationFixtures.set(darkKey, count: 4)])
    let channel = try #require(plan.calibration.first)
    let dark = try #require(channel.cells.first)
    #expect(dark.status == .build(frames: 4))
    #expect(plan.sourceSet(of: dark)?.key == darkKey)
    let bias = try #require(channel.cells.last)
    #expect(bias.status == .missing)
    #expect(plan.sourceSet(of: bias) == nil)
  }

  @Test("an excluded master is not the applied one: it reads as a plain match")
  func testExcludedIsNotChosen() throws {
    let library = [
      CalibrationFixtures.master(
        .dark, path: "/lib/d300_-15.fits", exposureMs: 300_000, tempC: -15, fromLibrary: true)
    ]
    var request = ImportRequest(paths: ["/c"])
    request.calibExclude = [CalibrationMatcher.suggestionID(Self.light, role: .dark)]
    var inventory = Inventory(root: "", frames: [])
    inventory.sets = [CalibrationFixtures.set(Self.light)]
    let plan = ImportPlan(inventory: inventory, library: library, request: request)
    let channel = try #require(plan.calibration.first)
    let dark = try #require(channel.cells.first)
    #expect(plan.alternatives(for: dark, of: channel).map(\.verdict) == [.matches])
  }
}
