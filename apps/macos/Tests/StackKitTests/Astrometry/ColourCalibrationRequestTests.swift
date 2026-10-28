import Foundation
import StackKit
import Testing

/// Card 0140: SPCC's OSC and mono forms as Siril 1.4.4 reads them (`help spcc`: `-monosensor=`
/// with `-rfilter=`/`-gfilter=`/`-bfilter=`, or `-oscsensor=` with `-oscfilter=`).
@Suite("ColourCalibrationRequest: the OSC and mono SPCC lines; Siril's mono lists read")
struct ColourCalibrationRequestTests {
  static let reference = "Average Spiral Galaxy"

  @Test(
    "testArguments: every name written out, quoted, in Siril's order",
    arguments: [
      (
        ColourCalibrationRequest.Method.spcc(
          sensor: "Sony IMX571", filter: "UV/IR Block", whiteReference: reference),
        #"spcc "-oscsensor=Sony IMX571" "-oscfilter=UV/IR Block""#
          + #" "-whiteref=Average Spiral Galaxy" -bgtol=2.8,2 -catalog=localgaia"#
      ),
      (
        .monoSPCC(
          sensor: "ZWO ASI1600MM", red: "Baader R", green: "Baader G", blue: "Baader B",
          whiteReference: reference),
        #"spcc "-monosensor=ZWO ASI1600MM" "-rfilter=Baader R" "-gfilter=Baader G""#
          + #" "-bfilter=Baader B" "-whiteref=Average Spiral Galaxy" -bgtol=2.8,2"#
          + " -catalog=localgaia"
      ),
      (.pcc, "pcc -bgtol=2.8,2 -catalog=localgaia"),
    ])
  func testArguments(method: ColourCalibrationRequest.Method, expected: String) {
    let request = ColourCalibrationRequest(
      method: method, limitMag: nil, backgroundTolerance: (below: 2.8, above: 2),
      catalogue: .localGaia)
    #expect(request.command.line == expected)
  }

  @Test("the names a request needs Siril to list, by kind; none for PCC")
  func testNames() {
    let mono = ColourCalibrationRequest.Method.monoSPCC(
      sensor: "S", red: "R", green: "G", blue: "B", whiteReference: "W")
    #expect(
      mono.names == [
        .monoSensor: "S", .redFilter: "R", .greenFilter: "G", .blueFilter: "B",
        .whiteReference: "W",
      ])
    #expect(
      ColourCalibrationRequest.Method.spcc(sensor: "S", filter: "F", whiteReference: "W").names
        == [.sensor: "S", .filter: "F", .whiteReference: "W"])
    #expect(ColourCalibrationRequest.Method.pcc.names.isEmpty)
  }

  @Test("Siril's mono lists, recorded on 2026-10-27, read by heading")
  func testMonoLists() throws {
    let url = try #require(
      Bundle.module.url(
        forResource: "mono-lists", withExtension: "log", subdirectory: "Fixtures/colourcal"))
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
      SirilLine(parsing: String($0)).text
    }
    let lists = ColourCalibrator.lists(lines)
    #expect(lists["monosensor"]?.contains("ZWO ASI1600MM") == true)
    #expect(lists["monosensor"]?.count == 15)
    #expect(lists["redfilter"]?.count == 13 && lists["greenfilter"]?.count == 13)
    #expect(lists["bluefilter"]?.count == 11)
  }
}
