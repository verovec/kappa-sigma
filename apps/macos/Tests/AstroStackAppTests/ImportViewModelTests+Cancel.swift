import AstroStackApp
import Foundation
import StackKit
import Testing

extension ImportViewModelTests {
  @Test("cancelling the rescan an exclusion started puts the exclusion list back with the request")
  func testCancelScanRestoresExclusions() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    let row = try #require(model.plan?.nights.first?.sets.first)
    model.exclude(row)
    #expect(model.excludedRows == [row] && model.isScanning)
    model.cancelScan()
    #expect(model.excludedRows.isEmpty && model.request.excludeSets.isEmpty)
  }

  @Test("cancelling the scan after a failure keeps the failed request and its overrides")
  func testCancelScanAfterFailure() async throws {
    let planner = FakePlanner()
    planner.failure = InspectError.noFolders
    let model = await Self.model(planner)
    #expect(model.error != nil)
    model.setColorModel(.osc)
    model.cancelScan()
    #expect(model.request.paths == ["/c/M31-DB"] && model.request.colorModel == .osc)
    #expect(ImportSheet.content(of: model) == .failed)
  }

  @Test("a calibration change during a rescan still rescans, never only rematches")
  func testRescanSurvivesCalibrationChange() async throws {
    let planner = FakePlanner()
    let model = await Self.model(planner)
    let scans = planner.requests.count
    model.rescan()
    model.setForceCalibration(true)
    await model.settled()
    #expect(planner.requests.count > scans, "the rescan reached the planner")
    #expect(planner.requests.last?.forceCalibration == true)
  }
}
