import AstroStackApp
import Foundation
import StackKit
import Testing

/// The master disclosure of the Import sheet (card 0071): it shows StackKit's statistics and
/// warnings, and every choice lands in the request the planner receives — nothing is decided for
/// the user.
@MainActor
@Suite("MasterInspectViewModel — stats, warnings, exclude, force, rebuild")
struct MasterInspectViewModelTests {
  /// A light whose dark is a library master, a forced-only alternative, and the capture's darks.
  static let light = SetKey(
    type: .light, filter: "L", exposureMs: 300_000, gain: 139, offset: 21, tempBucketC: -15,
    bin: 1)
  static let darkKey = SetKey(
    type: .dark, exposureMs: 300_000, gain: 139, offset: 21, tempBucketC: -15, bin: 1)

  static func master(_ path: String, gain: Int = 139) -> CalibrationMaster {
    var master = CalibrationMaster(type: .dark, path: path)
    master.exposureMs = 300_000
    master.gain = gain
    master.offset = 21
    master.bin = 1
    master.tempMilliC = -15_000
    master.hasTemp = true
    master.frameCount = 20
    master.fromLibrary = true
    return master
  }

  static let library = [master("/lib/dark.fits"), master("/lib/dark_g0.fits", gain: 0)]

  /// A plan of one light set, its capture darks and the two library darks.
  static func planning(_ requests: Recorder) -> ImportViewModel.Planning {
    { @MainActor request in
      requests.requests.append(request)
      var inventory = Inventory(root: "/c", frames: [])
      inventory.sets = [
        FrameSet(key: light, frames: [CaptureFrame(path: "/c/l.fits")], indices: [0]),
        FrameSet(key: darkKey, frames: [CaptureFrame(path: "/c/d.fits")], indices: [1]),
      ]
      return ImportPlan(inventory: inventory, library: library, request: request)
    }
  }

  @MainActor
  final class Recorder {
    var requests: [ImportRequest] = []
    var inspected: [String] = []
    var rebuilt: [SetKey] = []
    var replaced: [Bool] = []
    /// The library file a first rebuild would overwrite.
    var existing: String?
    var previewed: [String] = []
    var stats = MasterStats(
      type: .dark, width: 10, height: 10, planes: [[Float](repeating: 0.01, count: 100)])

    var services: MasterServices {
      MasterServices(
        inspect: { @MainActor path in
          self.inspected.append(path)
          var inspection = MasterInspection(
            path: path, master: MasterInspectViewModelTests.library[0], width: 10, height: 10,
            planes: 1, frames: 20, builtAt: .distantPast, stats: self.stats, warnings: [])
          inspection.warnings = MasterWarning.all(for: self.stats)
          return inspection
        },
        rebuild: { @MainActor set, _, _, replace, onLine in
          if let existing = self.existing, !replace {
            throw CalibrationError.wouldReplace(path: existing, frames: 20)
          }
          self.rebuilt.append(set.key)
          self.replaced.append(replace)
          for percent in [10, 40] { onLine(SirilLine(parsing: "log: Stacking \(percent)%")) }
          return MasterBuilder.Result(masters: [], warnings: ["rebuilt"])
        },
        preview: { path in self.previewed.append(path) })
    }
  }

  static func model(_ recorder: Recorder) async throws -> (ImportViewModel, MasterInspectViewModel)
  {
    let sheet = ImportViewModel(planning: planning(recorder), masters: recorder.services)
    sheet.choose(folder: URL(fileURLWithPath: "/c"))
    await sheet.settled()
    let channel = try #require(sheet.plan?.calibration.first)
    let cell = try #require(channel.cells.first)
    return (sheet, MasterInspectViewModel(cell: cell, channel: channel, sheet: sheet))
  }

  @Test(
    "a crossed threshold shows its warning; the request is left exactly as it was",
    arguments: [
      ([Float](repeating: 0.01, count: 100), [MasterWarning.Kind]()),
      (
        [Float](repeating: 0.01, count: 90) + [Float](repeating: 1, count: 10),
        [.clipped, .hotPixels]
      ),
    ])
  func testWarningsFromStats(plane: [Float], kinds: [MasterWarning.Kind]) async throws {
    let recorder = Recorder()
    recorder.stats = MasterStats(type: .dark, width: 10, height: 10, planes: [plane])
    let (sheet, model) = try await Self.model(recorder)
    await model.load()
    #expect(recorder.inspected == ["/lib/dark.fits"])
    #expect(model.inspection?.stats == recorder.stats)
    #expect(model.warnings.map(\.kind) == kinds)
    #expect(sheet.request == ImportRequest(paths: ["/c"]), "a warning never excludes (R2)")
  }

  @Test("exclude and use-a-forced-match land in calib_exclude and force, nothing else")
  func testPickOtherSerialisesExclusionAndForce() async throws {
    let recorder = Recorder()
    let (sheet, model) = try await Self.model(recorder)
    await model.load()
    #expect(model.alternatives.map(\.verdict) == [.chosen, .needsForce])
    #expect(!model.isExcluded)

    model.exclude()
    await sheet.settled()
    var expected = ImportRequest(paths: ["/c"])
    expected.calibExclude = [CalibrationMatcher.suggestionID(Self.light, role: .dark)]
    #expect(sheet.request == expected)

    model.include()
    model.useForcedMatches()
    await sheet.settled()
    expected.calibExclude = []
    expected.forceCalibration = true
    #expect(sheet.request == expected)
  }

  @Test("rebuild stacks the capture set the master stands for, streams progress, then rescans")
  func testRebuild() async throws {
    let recorder = Recorder()
    let (sheet, model) = try await Self.model(recorder)
    #expect(model.canRebuild)
    await model.rebuild()
    await sheet.settled()
    #expect(recorder.rebuilt == [Self.darkKey])
    #expect(model.progress == 40)
    #expect(model.notes == ["rebuilt"])
    #expect(recorder.replaced == [false])
    #expect(recorder.requests.count == 2, "the plan is made again over the new library")
    model.preview()
    #expect(recorder.previewed == ["/lib/dark.fits"])
  }

  @Test("a rebuild over an existing library master waits for the user's yes, then replaces it")
  func testRebuildAsksBeforeReplacing() async throws {
    let recorder = Recorder()
    recorder.existing = "/lib/dark.fits"
    let (sheet, model) = try await Self.model(recorder)
    await model.rebuild()
    #expect(recorder.rebuilt.isEmpty)
    #expect(model.pendingReplace?.contains("/lib/dark.fits") == true)
    #expect(model.pendingReplace?.contains("20 frames") == true)
    #expect(model.error == nil)

    await model.rebuild(replace: true)
    await sheet.settled()
    #expect(recorder.replaced == [true])
    #expect(model.pendingReplace == nil)
  }

  @Test("an excluded master offers to include it back")
  func testExcludedIncludesBack() async throws {
    let recorder = Recorder()
    let (sheet, model) = try await Self.model(recorder)
    model.exclude()
    await sheet.settled()
    let channel = try #require(sheet.plan?.calibration.first)
    let excluded = MasterInspectViewModel(
      cell: try #require(channel.cells.first), channel: channel, sheet: sheet)
    #expect(excluded.isExcluded)
    excluded.include()
    await sheet.settled()
    #expect(sheet.request == ImportRequest(paths: ["/c"]))
  }
}
