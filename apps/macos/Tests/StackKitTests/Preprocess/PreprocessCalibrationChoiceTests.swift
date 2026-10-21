import Foundation
import StackKit
import TestSupport
import Testing

/// The run applies the calibration the Import sheet showed: a suggestion the user unchecked
/// (`calib_exclude`) is not applied to that light set, and only to that one.
@Suite("Preprocessor — the user's calibration choices reach the stack")
struct PreprocessCalibrationChoiceTests {
  static func master(_ role: CalibrationRole, _ selection: CalibrationSelection)
    -> CalibrationMaster?
  {
    switch role {
    case .dark: selection.dark
    case .flat: selection.flat
    case .bias: selection.bias
    }
  }

  @Test(
    "an unchecked master is dropped from its light set; the other sets keep theirs",
    .scratchDirectory, arguments: [CalibrationRole.dark, .flat, .bias])
  func testExcludedRoleIsNotApplied(_ role: CalibrationRole) async throws {
    var request = try PreprocessorTests.request("X\(role.rawValue)")
    let light = try #require(
      request.inventory.sets.first { $0.key.type == .light && $0.key.filter == "L" })
    request.settings.calibrationExcluded = [CalibrationMatcher.suggestionID(light.key, role: role)]

    let result = try await Preprocessor(tools: PreprocessorTests.tools(PipelineSiril()))
      .perform(request) { _ in }

    let channels = Dictionary(uniqueKeysWithValues: result.channels.map { ($0.filter, $0) })
    let excluded = try #require(channels["L"])
    #expect(Self.master(role, excluded.selection) == nil)
    for filter in ["R", "G", "B"] {
      #expect(
        channels[filter].flatMap { Self.master(role, $0.selection) } != nil,
        "\(filter) keeps its \(role)")
    }
  }
}
