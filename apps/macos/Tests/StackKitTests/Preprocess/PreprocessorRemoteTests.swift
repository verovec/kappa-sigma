import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0181, end to end: a run whose calibration frames live in a bucket lists them before step 1,
/// and a second run over the same unchanged frames reuses the masters the first one built.
@Suite("Preprocessor — a bucket's calibration masters reused across runs")
struct PreprocessorRemoteTests {
  @Test(
    "testSecondRunReusesTheBucketsMasters: the second run downloads no calibration frame",
    .scratchDirectory)
  func testSecondRunReusesTheBucketsMasters() async throws {
    let night = try RemoteCalibrationTests.RemoteCalibration.make()
    let root = night.work.deletingLastPathComponent().deletingLastPathComponent()
    let preprocessor = Preprocessor(tools: PreprocessorTests.tools(PipelineSiril()))
    func request(_ run: String, library: [CalibrationMaster]) -> PreprocessRequest {
      var request = PreprocessRequest(
        inventory: night.inventory, output: root.appendingPathComponent("out/TESTFIELD/\(run)"),
        work: root.appendingPathComponent("work/run_\(run)"), runID: run, library: library)
      request.remoteStores = [night.bucket.store]
      return request
    }

    let first = try await preprocessor.perform(request("R1", library: []), sink: { _ in })
    let downloaded = night.bucket.downloaded.count
    #expect(downloaded > 0, "the first run reads the bucket's calibration frames to build")

    let second = try await preprocessor.perform(
      request("R2", library: RemoteCalibrationTests.library(first.masters)), sink: { _ in })

    #expect(
      second.warnings.contains { $0.contains("reused library master") },
      "the .sig proves the same bytes: \(second.warnings)")
    #expect(
      night.bucket.downloaded.count == downloaded,
      "not one calibration frame downloaded again: \(night.bucket.downloaded.count - downloaded)")
  }
}
