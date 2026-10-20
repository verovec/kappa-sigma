import StackKit
import Testing

/// Translated from `internal/inspect/temperature_test.go` and the grouping half of
/// `session_test.go`.
@Suite("FrameSet.group — set keys, temperature clusters, night split")
struct FrameSetTests {
  static func frame(_ type: FrameType, celsius: Double, index: Int) -> CaptureFrame {
    var frame = CaptureFrame(path: "/f/\(type.rawValue)_\(String(format: "%03d", index)).fit")
    frame.type = type
    frame.exposureMs = 60000
    frame.gain = 100
    frame.offset = 50
    frame.binX = 1
    frame.binY = 1
    frame.tempMilliC = Int(celsius * 1000)
    frame.hasTemp = true
    return frame
  }

  static func frames(_ type: FrameType, _ temps: [Double]) -> [CaptureFrame] {
    temps.enumerated().map { frame(type, celsius: $0.element, index: $0.offset) }
  }

  static func night(
    _ type: FrameType, _ filter: String, _ night: String, exposureMs: Int, gain: Int
  ) -> CaptureFrame {
    var frame = CaptureFrame(path: "")
    frame.type = type
    frame.filter = filter
    frame.session = night
    frame.exposureMs = exposureMs
    frame.gain = gain
    frame.offset = 10
    frame.binX = 1
    frame.binY = 1
    if !night.isEmpty { frame.dateObsMs = 1 }
    return frame
  }

  static func shape(_ sets: [FrameSet]) -> [String] {
    sets.map { "\($0.count)@\($0.key.tempBucketC)" }
  }

  struct TemperatureCase: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let type: FrameType
    let temps: [Double]
    let expected: [String]
  }

  static let temperatureCases: [TemperatureCase] = [
    TemperatureCase(
      testDescription: "a cooler regulating at -9.8 stays ONE set across both grid edges",
      type: .dark, temps: [-9.8, -7.4, -12.4, -9.9, -10.1, -7.6, -12.2], expected: ["7@-10"]),
    TemperatureCase(
      testDescription: "sub-degree drift never splits", type: .dark,
      temps: [-19.5, -20.0, -20.5, -19.8, -20.2], expected: ["5@-20"]),
    TemperatureCase(
      testDescription: "a cooler still ramping leaves its settling frames behind", type: .dark,
      temps: [-20.3, -20.1, -20.0, -16.3, -12.3, -10.3, -10.0, -10.0, -9.4],
      expected: ["3@-20", "1@-16", "5@-10"]),
    TemperatureCase(
      testDescription: "a long slow ramp is capped rather than chained into one master",
      type: .dark, temps: [-20, -19, -18, -17, -16, -15, -14, -13, -12, -11, -10],
      expected: ["6@-17", "5@-12"]),
    TemperatureCase(
      testDescription: "the span cap's trailing straggler rejoins its ramp", type: .dark,
      temps: [-20.3, -19.3, -15.3, -12.6, -11.5, -11.1, -10.8, -10.5, -10.3, -10.2],
      expected: ["2@-19", "8@-11"]),
    TemperatureCase(
      testDescription: "a two-frame straggler rejoins too", type: .dark,
      temps: [-16, -14, -12.5, -11.5, -11.2, -11, -10.9, -10.8], expected: ["8@-11"]),
    TemperatureCase(
      testDescription: "genuinely different set points stay apart", type: .dark,
      temps: [-20.1, -20.0, -19.9, -10.1, -10.0, -9.9], expected: ["3@-20", "3@-10"]),
    TemperatureCase(
      testDescription: "flats are not grouped by temperature at all", type: .flat,
      temps: [-8.7, -5.0, 0.0, 5.0, 10.0, 16.1], expected: ["6@0"]),
    TemperatureCase(
      testDescription: "bias has no temperature", type: .bias, temps: [-17.6, -15.0, -14.0],
      expected: ["3@0"]),
  ]

  @Test("temperature is decided per group, by gaps, capped in span", arguments: temperatureCases)
  func testFrameSet_temperature(row: TemperatureCase) {
    #expect(Self.shape(FrameSet.group(Self.frames(row.type, row.temps))) == row.expected)
  }

  @Test("a frame without a temperature never pools with frames near 0 °C")
  func testFrameSet_noTemperatureStaysApart() {
    var noTemp = Self.frame(.dark, celsius: 0, index: 99)
    noTemp.tempMilliC = 0
    noTemp.hasTemp = false
    let sets = FrameSet.group(Self.frames(.dark, [-0.2, 0.1]) + [noTemp])
    #expect(sets.count == 2)
    #expect(sets.allSatisfy { $0.key.tempBucketC == 0 })
    #expect(sets.map(\.count).reduce(0, +) == 3)
  }

  @Test("a cluster's frames come back in path order; its label is the median")
  func testFrameSet_clusterOrderAndMedian() {
    let ordered = FrameSet.group(Self.frames(.dark, [-10.2, -9.8, -10.0]))
    #expect(ordered.count == 1)
    #expect(ordered.first?.frames.map(\.path) == ["/f/DARK_000.fit", "/f/DARK_001.fit", "/f/DARK_002.fit"])
    let median = FrameSet.group(Self.frames(.dark, [-12.0, -10.0, -10.0, -10.0, -9.0]))
    #expect(median.first?.key.tempBucketC == -10)
  }

  @Test("one night keeps the pre-sessionization keys: no set carries a night")
  func testFrameSet_singleNight() {
    let sets = FrameSet.group([
      Self.night(.light, "L", "2023-02-27", exposureMs: 30000, gain: 250),
      Self.night(.light, "L", "2023-02-27", exposureMs: 30000, gain: 250),
      Self.night(.flat, "L", "2023-02-27", exposureMs: 5, gain: 0),
      Self.night(.dark, "", "2023-02-27", exposureMs: 30000, gain: 250),
      Self.night(.bias, "", "2023-02-27", exposureMs: 0, gain: 250),
    ])
    #expect(sets.count == 4)
    #expect(sets.allSatisfy { $0.key.session.isEmpty })
  }

  @Test("two nights split lights and flats per night; darks and bias pool")
  func testFrameSet_multiNight() {
    let frames = ["2023-02-27", "2023-03-15"].flatMap { night in
      [
        Self.night(.light, "L", night, exposureMs: 30000, gain: 250),
        Self.night(.flat, "L", night, exposureMs: 5, gain: 0),
        Self.night(.dark, "", night, exposureMs: 30000, gain: 250),
        Self.night(.bias, "", night, exposureMs: 0, gain: 250),
      ]
    }
    let sets = FrameSet.group(frames)
    let sessions = { (type: FrameType) in sets.filter { $0.key.type == type }.map(\.key.session) }
    #expect(sessions(.light) == ["2023-02-27", "2023-03-15"])
    #expect(sessions(.flat).count == 2)
    #expect(sessions(.dark) == [""])
    #expect(sessions(.bias) == [""])
  }

  @Test("one night plus undated strays does not split; two nights give strays their own set")
  func testFrameSet_undated() {
    let one = FrameSet.group([
      Self.night(.light, "L", "2023-02-27", exposureMs: 30000, gain: 250),
      Self.night(.light, "L", "", exposureMs: 30000, gain: 250),
    ])
    #expect(one.map(\.key.session) == [""])
    let two = FrameSet.group([
      Self.night(.light, "L", "2023-02-27", exposureMs: 30000, gain: 250),
      Self.night(.light, "L", "2023-03-15", exposureMs: 30000, gain: 250),
      Self.night(.light, "L", "", exposureMs: 30000, gain: 250),
    ])
    #expect(two.map(\.key.session) == ["", "2023-02-27", "2023-03-15"])
  }

  @Test(
    "the set id is the stored exclusion token, field order fixed",
    arguments: [
      (
        SetKey(
          type: .light, object: "M101", filter: "R", exposureMs: 120_000, gain: 139, offset: 21,
          tempBucketC: -10, bin: 1, session: "2026-06-14"),
        "LIGHT|M101|R|e120000|g139o21b1|i0|t-10|s:2026-06-14"
      ),
      (SetKey(type: .bias, gain: 139, offset: 21, bin: 1), "BIAS|||e0|g139o21b1|i0|t0|s:"),
    ])
  func testSetKey_id(key: SetKey, expected: String) {
    #expect(key.id == expected)
  }

  @Test("a colour set and a mono set of the same settings are two sets")
  func testFrameSet_colorSeparates() {
    var color = Self.night(.light, "", "", exposureMs: 30000, gain: 100)
    color.bayer = "RGGB"
    let sets = FrameSet.group([color, Self.night(.light, "", "", exposureMs: 30000, gain: 100)])
    #expect(sets.count == 2)
    #expect(Set(sets.map(\.key.color)) == [true, false])
  }
}
