import Foundation
import StackKit
import Testing

/// Every script the legacy engine ran in the committed oracle cases, rebuilt with the Swift
/// builders from the parameters the run used, must render byte-equal to the recording.
@Suite("SirilScript renders the legacy engine's .ssf scripts byte for byte")
struct SirilScriptTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let oracle: String
    let file: String
    let script: SirilScript
    var testDescription: String { "\(oracle)/\(file)" }
  }

  static let work = "<ROOT>/work/run_<RUN>"
  static let masters = "\(work)/masters"
  static let out = "<ROOT>/out/TESTFIELD/<RUN>"
  static let bias = "\(masters)/master_BIAS_g100o10_b1"
  static let dark10 = "\(masters)/master_DARK_10000ms_g100o10_b1_-10C"
  static let dark30 = "\(masters)/master_DARK_30000ms_g100o10_b1_-10C"

  static func calib(dark: String, flat: String) -> CalibrationMasters {
    CalibrationMasters(dark: "\(dark).fits", flat: "\(flat).fits")
  }

  static func stackLights(_ filter: String, registered: String, count: Int) -> SirilScript {
    SirilScripts.stackSelected(
      registered: registered, count: count, rejected: [], out: "\(out)/master_\(filter)",
      options: .lights)
  }

  /// The tail every run ends with: combine, neutralize, finish, mono luminance.
  static func finishRows(_ oracle: String, first: Int, combine: SirilScript) -> [Row] {
    let lin = "\(work)/05_stretched/lum_mono_lin.fits"
    let mono = "\(work)/05_stretched/lum_mono"
    let scripts = [
      combine,
      SirilScripts.neutralize(load: "combined", out: "combined", backgroundDegree: 1, scnr: 0),
      SirilScripts.finish(
        load: "combined", out: "final", linked: true, saturation: 0.12, formats: [.png, .tif]),
      SirilScripts.monoStretch(linear: lin, stretched: mono, backgroundDegree: 1, target: 0.06),
      SirilScripts.export(load: mono, base: mono, formats: [.tif]),
      SirilScripts.export(
        load: "\(mono).tif", base: "\(out)/final_luminance", formats: [.tif, .png]),
    ]
    return scripts.enumerated().map { offset, script in
      Row(oracle: oracle, file: String(format: "%04d_<RUN>.ssf", first + offset), script: script)
    }
  }

  static let singleNight = singleNightRows()
  static let twoNight =
    (twoNightMasterRows() + twoNightChannelRows()).map {
      Row(oracle: "golden-two-night", file: $0.0, script: $0.1)
    } + twoNightTailRows()

  static func singleNightRows() -> [Row] {
    let flat = "\(masters)/master_FLAT_5ms_g100o10_b1_0C"
    var rows = [
      Row(
        oracle: "golden-single-night", file: "0001_cal_master_BIAS_g100o10_b1.ssf",
        script: SirilScripts.stackMaster(seq: "cal", out: bias, frames: 3, options: .bias)),
      Row(
        oracle: "golden-single-night", file: "0002_cal_master_DARK_10000ms_g100o10_b1_-10C.ssf",
        script: SirilScripts.stackMaster(seq: "cal", out: dark10, frames: 3, options: .dark)),
      Row(
        oracle: "golden-single-night", file: "0003_cal_master_FLAT_5ms_g100o10_b1_0C.ssf",
        script: SirilScripts.stackFlat(
          seq: "cal", out: flat, bias: "\(bias).fits", frames: 3, options: .flat)),
    ]
    for (index, filter) in ["L", "R", "G", "B"].enumerated() {
      rows.append(
        Row(
          oracle: "golden-single-night",
          file: String(format: "%04d_light_\(filter).ssf", 4 + 2 * index),
          script: SirilScripts.calibrateRegister(
            seq: "light", masters: calib(dark: dark10, flat: flat))))
      rows.append(
        Row(
          oracle: "golden-single-night",
          file: String(format: "%04d_light_\(filter).ssf", 5 + 2 * index),
          script: stackLights(filter, registered: "r_pp_light", count: 3)))
    }
    for (index, filter) in ["L", "R", "G", "B"].enumerated() {
      rows.append(
        Row(
          oracle: "golden-single-night", file: String(format: "%04d_<RUN>.ssf", 12 + index),
          script: SirilScripts.parityProbe(
            load: "master_\(filter)", out: "_parity_probe", coords: nil)))
    }
    rows.append(
      Row(
        oracle: "golden-single-night", file: "0016_04_aligned.ssf",
        script: SirilScripts.alignMasters(seq: "ch")))
    rows += finishRows(
      "golden-single-night", first: 17,
      combine: SirilScripts.combine(
        .lrgb(lum: "trim_L", r: "trim_R", g: "trim_G", b: "trim_B"), backgroundDegree: 1))
    return rows
  }

  static let flatA = "\(masters)/master_FLAT_5ms_g100o10_b1_0C_n2024-03-01"
  static let flatB = "\(masters)/master_FLAT_B_5ms_g100o10_b1_0C_n2020-05-15"

  /// Two-night case, 0001–0005: the masters.
  static func twoNightMasterRows() -> [(String, SirilScript)] {
    [
      (
        "0001_cal_master_BIAS_g100o10_b1.ssf",
        SirilScripts.stackMaster(seq: "cal", out: bias, frames: 3, options: .bias)
      ),
      (
        "0002_cal_master_DARK_10000ms_g100o10_b1_-10C.ssf",
        SirilScripts.stackMaster(seq: "cal", out: dark10, frames: 3, options: .dark)
      ),
      (
        "0003_cal_master_DARK_30000ms_g100o10_b1_-10C.ssf",
        SirilScripts.stackMaster(seq: "cal", out: dark30, frames: 3, options: .dark)
      ),
      (
        "0004_cal_master_FLAT_5ms_g100o10_b1_0C_n2024-03-01.ssf",
        SirilScripts.stackFlat(
          seq: "cal", out: flatA, bias: "\(bias).fits", frames: 3, options: .flat)
      ),
      (
        "0005_cal_master_FLAT_B_5ms_g100o10_b1_0C_n2020-05-15.ssf",
        SirilScripts.stackFlat(
          seq: "cal", out: flatB, bias: "\(bias).fits", frames: 3, options: .flat)
      ),
    ]
  }

  /// Two-night case, 0006–0027: per-night calibration, probes, merge, graded stacks.
  static func twoNightChannelRows() -> [(String, SirilScript)] {
    let nightA = calib(dark: dark10, flat: flatA)
    let nightB = calib(dark: dark30, flat: flatB)
    let probe = SirilScripts.parityProbe(load: "pp_light_00001", out: "_parity_probe", coords: nil)
    let flatten = SirilScripts.flattenRegister2Pass(
      seq: "light", transformation: "homography", degree: 1)
    let register = SirilScripts.register2Pass(seq: "light", transformation: "homography")
    func apply(_ reference: Int) -> SirilScript {
      SirilScripts.applyRegistration(seq: "light", reference: reference, framing: "current")
    }
    func calibrate(_ masters: CalibrationMasters) -> SirilScript {
      SirilScripts.calibrateOnly(seq: "light", masters: masters)
    }
    return [
      ("0006_light_L_g0.ssf", calibrate(nightB)), ("0007_light_L_g0.ssf", probe),
      ("0008_light_L_g1.ssf", calibrate(nightA)), ("0009_light_L_g1.ssf", probe),
      ("0010_merged_L.ssf", flatten), ("0011_merged_L.ssf", register),
      ("0012_merged_L.ssf", apply(4)),
      ("0013_merged_L.ssf", stackLights("L", registered: "r_light", count: 10)),
      ("0014_light_R_g0.ssf", calibrate(nightB)), ("0015_light_R_g1.ssf", calibrate(nightA)),
      ("0016_merged_R.ssf", flatten), ("0017_merged_R.ssf", register),
      ("0018_merged_R.ssf", apply(4)),
      ("0019_merged_R.ssf", stackLights("R", registered: "r_light", count: 10)),
      ("0020_light_G_g0.ssf", calibrate(nightA)), ("0021_merged_G.ssf", register),
      ("0022_merged_G.ssf", apply(2)),
      ("0023_merged_G.ssf", stackLights("G", registered: "r_light", count: 3)),
      ("0024_light_B_g0.ssf", calibrate(calib(dark: dark10, flat: flatB))),
      ("0025_merged_B.ssf", register), ("0026_merged_B.ssf", apply(2)),
      ("0027_merged_B.ssf", stackLights("B", registered: "r_light", count: 3)),
    ]
  }

  /// Two-night case, 0028–0038: master probes, channel alignment, the finish.
  static func twoNightTailRows() -> [Row] {
    let oracle = "golden-two-night"
    let probes = ["L", "R", "G", "B"].enumerated().map { index, filter in
      Row(
        oracle: oracle, file: String(format: "%04d_<RUN>.ssf", 28 + index),
        script: SirilScripts.parityProbe(
          load: "master_\(filter)", out: "_parity_probe", coords: nil))
    }
    let align = Row(
      oracle: oracle, file: "0032_04_aligned.ssf", script: SirilScripts.alignMasters(seq: "ch"))
    return probes + [align]
      + finishRows(
        oracle, first: 33,
        combine: SirilScripts.combine(
          .lrgb(lum: "aligned_L", r: "aligned_R", g: "aligned_G", b: "aligned_B"),
          backgroundDegree: 1))
  }

  static func recorded(_ row: Row) throws -> String {
    let url = try #require(
      Bundle.module.url(
        forResource: row.file, withExtension: nil,
        subdirectory: "Fixtures/oracle/\(row.oracle)/scripts"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  @Test("rendered text is byte-equal to the recorded file", arguments: singleNight + twoNight)
  func testRenderMatchesRecordedScripts(_ row: Row) throws {
    #expect(row.script.render() == (try Self.recorded(row)))
  }

  @Test("the table covers every recorded script of both committed cases")
  func testSirilScript_tableCoversEveryRecording() throws {
    for (oracle, rows) in [
      ("golden-single-night", Self.singleNight), ("golden-two-night", Self.twoNight),
    ] {
      let folder = try #require(
        Bundle.module.url(
          forResource: "scripts", withExtension: nil, subdirectory: "Fixtures/oracle/\(oracle)"))
      let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter {
        $0.hasSuffix(".ssf")
      }
      #expect(Set(rows.map(\.file)) == Set(files), "\(oracle)")
    }
  }
}
