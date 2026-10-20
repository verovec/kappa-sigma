import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// The Import sheet's state: every control edits the request the planner receives, the plan
/// shown is the planner's, and nothing in between decides anything.
@MainActor
@Suite("ImportViewModel — overrides into the request, the plan out of StackKit")
struct ImportViewModelTests {
  /// Records every request and answers with a plan of `sets` (all on one night).
  @MainActor
  final class FakePlanner {
    var requests: [ImportRequest] = []
    var failure: (any Error)?

    nonisolated static func frame(_ key: SetKey) -> CaptureFrame {
      var frame = CaptureFrame(path: "/c/\(key.type.rawValue)_\(key.filter).fits")
      frame.type = key.type
      frame.session = "2026-10-17"
      return frame
    }

    nonisolated static let sets: [FrameSet] = [
      FrameSet(
        key: SetKey(type: .light, object: "M 31", filter: "RGB", exposureMs: 300_000, color: true),
        frames: [frame(SetKey(type: .light, filter: "RGB"))], indices: [0]),
      FrameSet(
        key: SetKey(type: .light, object: "M 31", filter: "Ha", exposureMs: 300_000),
        frames: [frame(SetKey(type: .light, filter: "Ha"))], indices: [1]),
      FrameSet(
        key: SetKey(type: .bias, gain: 100), frames: [frame(SetKey(type: .bias))], indices: [2]),
    ]

    var planning: ImportViewModel.Planning {
      { @MainActor request in
        self.requests.append(request)
        if let failure = self.failure { throw failure }
        var inventory = Inventory(root: request.paths.first ?? "", frames: [])
        inventory.sets = Self.sets.filter { !request.excludeSets.contains($0.key.id) }
        inventory.warnings = ["a warning"]
        return ImportPlan(inventory: inventory, library: [], request: request)
      }
    }
  }

  static func model(_ planner: FakePlanner) async -> ImportViewModel {
    let model = ImportViewModel(planning: planner.planning)
    model.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await model.settled()
    return model
  }

  @Test("choosing a folder scans it with no override and shows the planner's plan")
  func testChooseFolder() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    #expect(planner.requests == [ImportRequest(paths: ["/c/M31-DB"])])
    #expect(model.plan?.nights.map(\.session) == ["2026-10-17", ""], "bias is shared calibration")
    #expect(model.plan?.nights.flatMap(\.sets).count == 3)
    #expect(model.plan?.warnings == ["a warning"])
    #expect(!model.isScanning)
    #expect(model.error == nil)
  }

  @Test("each control lands in its own request field, and only there")
  func testOverridesReachTheRequest() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    let rows = try #require(model.plan?.nights.first?.sets)

    model.setFilterSet(.dualband, for: rows[0])
    model.mapFilter("Ha", to: "ignore")
    model.setColorModel(.osc)
    model.setForceCalibration(true)
    let cell = try #require(model.plan?.calibration.first?.cells.first)
    model.setIncluded(false, cell)
    await model.settled()

    var expected = ImportRequest(paths: ["/c/M31-DB"])
    expected.filterSets = [rows[0].id: .dualband]
    expected.filterMap = ["Ha": "ignore"]
    expected.colorModel = .osc
    expected.forceCalibration = true
    expected.calibExclude = [cell.suggestionID]
    #expect(planner.requests.last == expected)

    model.setFilterSet(.unknown, for: rows[0])
    model.mapFilter("Ha", to: nil)
    model.setIncluded(true, cell)
    model.setColorModel(.auto)
    model.setForceCalibration(false)
    await model.settled()
    #expect(planner.requests.last == ImportRequest(paths: ["/c/M31-DB"]), "back to detection")
  }

  @Test("an excluded set leaves the plan but stays listed, and can be restored")
  func testExcludeAndRestore() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    let ha = try #require(model.plan?.nights.first?.sets.first { $0.filter == "Ha" })

    model.exclude(ha)
    await model.settled()
    #expect(planner.requests.last?.excludeSets == [ha.id])
    #expect(model.plan?.nights.first?.sets.contains { $0.id == ha.id } == false)
    #expect(model.excludedRows == [ha])

    model.restore(ha)
    await model.settled()
    #expect(planner.requests.last?.excludeSets == [])
    #expect(model.excludedRows.isEmpty)
  }

  @Test("a failed scan shows its error and keeps no stale plan")
  func testScanFailure() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    planner.failure = InspectError.unreadableFolder("/c/M31-DB")
    model.rescan()
    await model.settled()
    #expect(model.plan == nil)
    #expect(model.error == .inspect(.unreadableFolder("/c/M31-DB")))
  }

  @Test("the light filters offered for mapping are the scan's own, in canonical order")
  func testMappableFilters() async {
    let model = await Self.model(FakePlanner())
    #expect(model.lightFilters == ["Ha", "RGB"])
    #expect(ImportViewModel.channels == ["L", "R", "G", "B", "Ha", "OIII", "SII", "ignore"])
  }

  @Test("a calibration-only choice replans the last scan; a scan override rescans")
  func testCalibrationChoiceDoesNotRescan() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    let cell = try #require(model.plan?.calibration.first?.cells.last)
    model.setForceCalibration(true)
    await model.settled()
    let forced = try #require(model.plan?.calibration.first?.cells.last)
    #expect(forced.status != cell.status, "force matches the bias of another gain")
    model.setIncluded(false, forced)
    await model.settled()
    #expect(planner.requests.count == 1, "no rescan for calibration choices")
    #expect(model.plan?.calibration.first?.cells.last?.status == .excluded(forced.status))
    model.setColorModel(.osc)
    await model.settled()
    #expect(planner.requests.count == 2)
    #expect(planner.requests.last?.calibExclude == [forced.suggestionID])
  }

  @Test("mapping offers the scan's original filters, and a remapped set cannot be excluded")
  func testMappedFilters() async throws {
    let model = await Self.model(FakePlanner())
    let rgb = try #require(model.plan?.nights.first?.sets.first { $0.filter == "RGB" })
    model.mapFilter("Ha", to: "RGB")
    await model.settled()
    #expect(model.lightFilters == ["Ha"], "RGB is now only a mapping target")
    #expect(!model.canExclude(rgb), "its id after the map is not the id the scan excludes by")
    model.mapFilter("Ha", to: nil)
    await model.settled()
    #expect(model.canExclude(rgb))
  }
}
