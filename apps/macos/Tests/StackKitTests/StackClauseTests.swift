import StackKit
import Testing

/// The rules of `stackclause.go` / `catalogue.go` that no recorded script exercises, pinned with
/// the legacy unit tests' expectations (scripts_test.go, stackclause_test.go).
@Suite("StackClause: the stack options Siril reads, in the legacy order")
struct StackClauseTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let options: StackOptions
    let frames: Int
    let expected: String
    var testDescription: String { name }
  }

  static func lights(_ change: (inout StackOptions) -> Void) -> StackOptions {
    var options = StackOptions.lights
    change(&options)
    return options
  }

  static let cases: [Case] = [
    Case(
      name: "auto, 3 frames → percentile", options: .lights, frames: 3,
      expected: "rej percentile 0.2 0.1 -norm=addscale -output_norm -weight=wfwhm"),
    Case(
      name: "auto, 7 frames → percentile", options: .lights, frames: 7,
      expected: "rej percentile 0.2 0.1 -norm=addscale -output_norm -weight=wfwhm"),
    Case(
      name: "auto, 8 frames → winsorized", options: .lights, frames: 8,
      expected: "rej winsorized 3 3 -norm=addscale -output_norm -weight=wfwhm"),
    Case(
      name: "auto, 50 frames → generalized", options: .lights, frames: 50,
      expected: "rej generalized 0.3 0.05 -norm=addscale -output_norm -weight=wfwhm"),
    Case(
      name: "auto, 0 frames → winsorized", options: .bias, frames: 0,
      expected: "rej winsorized 3 3 -nonorm"),
    Case(
      name: "fast norm and rejection maps",
      options: lights {
        $0.rejection = .winsorized
        $0.weight = nil
        $0.fastNormalization = true
        $0.rejectionMaps = true
      }, frames: 12,
      expected: "rej winsorized 3 3 -norm=addscale -fastnorm -output_norm -rejmaps"),
    Case(
      name: "no normalization keeps output_norm after -nonorm",
      options: lights {
        $0.rejection = .winsorized
        $0.normalization = .none
        $0.weight = nil
      }, frames: 12, expected: "rej winsorized 3 3 -nonorm -output_norm"),
    Case(
      name: "explicit sigmas are clamped to the algorithm's range",
      options: lights {
        $0.rejection = .linearFit
        $0.low = 0.1
        $0.high = 42
        $0.weight = nil
      }, frames: 12, expected: "rej linear 0.5 10 -norm=addscale -output_norm"),
    Case(
      name: "median combine takes no rejection, keeps normalization",
      options: lights { $0.combine = .median }, frames: 12,
      expected: "med -norm=addscale -output_norm"),
    Case(
      name: "sum takes nothing else", options: lights { $0.combine = .sum }, frames: 12,
      expected: "sum"),
    Case(
      name: "rejection none",
      options: lights {
        $0.rejection = .none
        $0.weight = nil
      }, frames: 12, expected: "rej none -norm=addscale -output_norm"),
    Case(
      name: "feather",
      options: lights {
        $0.rejection = .winsorized
        $0.featherPx = 4
      }, frames: 12,
      expected: "rej winsorized 3 3 -norm=addscale -output_norm -weight=wfwhm -feather=4"),
    Case(
      name: "multiplicative flat", options: .flat, frames: 20,
      expected: "rej winsorized 3 3 -norm=mul"),
  ]

  @Test("clause text", arguments: cases)
  func testStackClause_render(_ testCase: Case) {
    #expect(StackClause.render(testCase.options, frames: testCase.frames) == testCase.expected)
  }

  @Test(
    "calibrate arguments, in the legacy order",
    arguments: [
      (CalibrationMasters(dark: "d.fits", flat: "f.fits"), "-dark=d.fits -flat=f.fits -cc=dark"),
      (CalibrationMasters(bias: "b.fits", flat: "f.fits"), "-flat=f.fits -bias=b.fits"),
      (
        CalibrationMasters(bias: "b.fits", dark: "d.fits", darkOptimize: true),
        "-dark=d.fits -bias=b.fits -cc=dark -opt"
      ),
      (
        CalibrationMasters(dark: "d.fits", flat: "f.fits", badPixelMap: "d_defects.lst", cfa: true),
        "-dark=d.fits -flat=f.fits -cc=bpm d_defects.lst -cfa -equalize_cfa -debayer"
      ),
      (CalibrationMasters(dark: "d.fits", cfa: true), "-dark=d.fits -cc=dark -cfa -debayer"),
      (CalibrationMasters(cfa: true), "-debayer"),
      (CalibrationMasters(), ""),
      // Empty paths are absent, as the legacy `!= ""` tests: no `-dark=`, the bias stays.
      (CalibrationMasters(bias: "b.fits", dark: "", flat: ""), "-bias=b.fits"),
    ])
  func testCalibrationMasters_arguments(masters: CalibrationMasters, expected: String) {
    #expect(masters.arguments.joined(separator: " ") == expected)
  }

  @Test("no calibration arguments: no calibrate line, no pp_ prefix")
  func testSirilScripts_calibrateOnly_withoutMasters() {
    let script = SirilScripts.calibrateOnly(seq: "light", masters: CalibrationMasters())
    #expect(script.render() == "requires 1.2.0\nsetext fits\nset32bits\nlink light -out=.\n")
  }
}
