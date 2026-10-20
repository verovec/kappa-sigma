import Foundation
import StackKit
import TestSupport
import Testing

/// The knobs a run applies: the legacy presets (`mode.Preset`) and the plate-solve hint.
@Suite("PreprocessSettings — presets and the parity solve hint")
struct PreprocessSettingsTests {
  @Test("nebula grades leniently and fits a degree-2 sky; deepsky is the default")
  func testPresets() throws {
    let nebula = PreprocessSettings.preset(.nebula)
    #expect(nebula.grading.roundnessFloor == 0.50 && nebula.grading.roundnessSigma == 3.0)
    #expect(nebula.grading.fwhmSigma == 3.0 && nebula.grading.backgroundSigma == 3.0)
    #expect(nebula.grading.starCountFraction == 0.4 && nebula.backgroundDegree == 2)
    #expect(nebula.edgeCrop && nebula.dropWheelTransition && nebula.stack == .lights)
    #expect(PreprocessSettings.preset(.deepsky) == PreprocessSettings())
  }

  @Test("a request without settings applies its mode's preset", .scratchDirectory)
  func testRequestPreset() throws {
    let request = PreprocessRequest(
      inventory: try PreprocessorTests.request().inventory, output: try ScratchDirectory.url,
      work: try ScratchDirectory.url,
      runID: "R", mode: .nebula)
    #expect(request.settings == PreprocessSettings.preset(.nebula))
  }

  @Test("the solve hint reaches every parity probe's platesolve", .scratchDirectory)
  func testCoordinates() async throws {
    let (masters, _, _) = try ChannelAlignerTests.masters(["R", "G"])
    let siril = PipelineSiril()
    var journal = PreprocessJournal()
    try await ParityNormalizer(runner: siril.runner, coordinates: "10.68,41.27").normalize(
      masters, ordered: ["R", "G"], journal: &journal)
    let solves = siril.calls.flatMap { $0.script.split(separator: "\n") }
      .filter { $0.hasPrefix("platesolve") }
    #expect(solves.count == 2 && solves.allSatisfy { $0.contains("10.68,41.27") })
  }
}
