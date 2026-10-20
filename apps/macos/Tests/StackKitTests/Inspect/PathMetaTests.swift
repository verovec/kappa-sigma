import StackKit
import Testing

/// Translated from `internal/inspect/filename_test.go`.
@Suite("PathMeta — type, filter, gain and wheel slot from file and folder names")
struct PathMetaTests {
  @Test(
    "ASIStudio file names carry type, filter, exposure, gain, temperature and bin",
    arguments: [
      (
        "input/galaxy/L/Light_ASIImg_30sec_Bin1_filter-L_-20.0C_gain300_2025-03-27_232804_frame0001.fit",
        PathMeta(
          type: .light, filter: "L", exposureMs: 30000, gain: 300, tempMilliC: -20000,
          hasTemp: true, bin: 1)
      ),
      (
        "input/galaxy/Darks/Dark_ASIImg_30sec_Bin1_filter-B_-20.0C_gain300_2025-03-28_025415_frame0001.fit",
        PathMeta(
          type: .dark, filter: "B", exposureMs: 30000, gain: 300, tempMilliC: -20000,
          hasTemp: true, bin: 1)
      ),
      (
        "input/galaxy/Bias/Bias_ASIImg_0.001sec_Bin1_filter-L_-19.5C_gain300_2025-03-28_023107_frame0021.fit",
        PathMeta(
          type: .bias, filter: "L", exposureMs: 1, gain: 300, tempMilliC: -19500, hasTemp: true,
          bin: 1)
      ),
      (
        "input/galaxy/Flats/Ha/Flat_ASIImg_0.2sec_Bin1_filter-Ha_-20.0C_gain300_2025-03-28_031453_frame0001.fit",
        PathMeta(
          type: .flat, filter: "Ha", exposureMs: 200, gain: 300, tempMilliC: -20000,
          hasTemp: true, bin: 1)
      ),
    ])
  func testPathMeta_asiNames(path: String, expected: PathMeta) {
    #expect(PathMeta(path: path) == expected)
  }

  @Test("lights in per-filter folders take the folder's filter; a Darks folder types a frame")
  func testPathMeta_filterFromFolder() {
    #expect(PathMeta(path: "input/galaxy/G/Light_30sec_frame1.fit").filter == "G")
    #expect(PathMeta(path: "input/galaxy/Darks/something_30sec.fit").type == .dark)
  }

  @Test(
    "compound folder names type a frame by word, an explicit type beats SharpCap's CapObj",
    arguments: [
      ("input/2020_05_06/darks_0gain_300s_-25deg/autorun/x.fit", FrameType.dark),
      ("input/C2019/offset_-15_250gain/autorun/x.fit", .bias),
      ("input/2020_05_06/flats_0gain_Ha/autorun/x.fit", .flat),
      ("input/M27/offsets/2019-08-30_00_23/x.fit", .bias),
      ("input/M27/darks/2019-08-30_00_02/x.fit", .dark),
      ("input/sess/master_flats/x.fit", .flat),
      ("input/sess/dark_flats/x.fit", .darkFlat),
      ("input/sess/darkstar_nebula/L/x.fit", .unknown),
      ("input/M27/m27/data/2019-08-29_22_20/x.fit", .unknown),
      ("input/2023_02_27/darks/CapObj/2023-02-28_05_18_38Z/x.FIT", .dark),
      ("input/2023_02_27/offset/CapObj/2023-02-28_05_52_24Z/x.FIT", .bias),
      ("input/2023_02_27/flats/CapObj/2023-02-28_06_01_48Z/x.FIT", .flat),
      ("input/2023_02_27/triplet_m66/CapObj/2023-02-27_22_55_39Z/x.FIT", .light),
    ])
  func testPathMeta_typeFromFolders(path: String, expected: FrameType) {
    #expect(PathMeta.typeFromFolders(path) == expected)
  }

  @Test(
    "a filter folder is its first word, except calibration folders, where any word counts",
    arguments: [
      ("input/m33/L/2019/x.fit", "L"),
      ("input/M81_M82_2019/M81M82/V/2019/x.fit", "G"),
      ("input/M81_M82_2019/M81M82/R/2019/x.fit", "R"),
      ("input/sess/Red/x.fit", "R"),
      ("input/sess/Ha_300s/x.fit", "Ha"),
      ("input/sess/R band/x.fit", "R"),
      ("input/M27/m27/data/2019/x.fit", ""),
      ("input/2020_05_06/m81_m82_LRGB_0gain_Ha_180gain_120s/autorun/x.fit", ""),
      ("input/ngc6992/flats_0gain_Ha/autorun/x.fit", "Ha"),
      ("input/sess/darks_0gain_300s/x.fit", ""),
    ])
  func testPathMeta_filterFromFolders(path: String, expected: String) {
    #expect(PathMeta.filterFromFolders(path) == expected)
  }

  @Test(
    "a folder gain is read per word: 0gain_300s is gain 0, not 300",
    arguments: [
      ("input/2020/darks_0gain_300s_-25deg/autorun/x.fit", 0),
      ("input/C2019/offset_-15_250gain/autorun/x.fit", 250),
      ("input/sess/flats_0gain_Ha/x.fit", 0),
      ("input/sess/Light_gain300_30sec/x.fit", 300),
      ("input/sess/nogainhere/x.fit", 0),
    ])
  func testPathMeta_gainFromFolders(path: String, expected: Int) {
    #expect(PathMeta.gainFromFolders(path) == expected)
  }

  @Test(
    "SharpCap names carry the filter-wheel slot; ordinary names do not",
    arguments: [
      ("input/M33/CapObj/2021-08-14_00_47/2021-08-14-0047_6-1-CapObj_0000.FIT", 1),
      ("input/M27/data/2019/2019-08-29-2220_5-2-L_0000.FIT", 2),
      ("input/C2019/autorun/2020-04-13-2239_3-4-autorun_0018.FIT", 4),
      ("input/galaxy/L/Light_ASIImg_30sec_filter-L_frame0001.fit", 0),
    ])
  func testPathMeta_wheelSlot(path: String, expected: Int) {
    #expect(PathMeta(path: path).wheelSlot == expected)
  }

  @Test(
    "processed outputs are recognised by a whole word, copy counters included",
    arguments: [
      ("m27_R_stacked.tif", true), ("Autosave001.tif", true), ("master_dark.fits", true),
      ("Light_0001.fit", false), ("masterpiece_light.fit", false),
    ])
  func testPathMeta_isProcessedName(name: String, expected: Bool) {
    #expect(PathMeta.isProcessedName("/x/\(name)") == expected)
  }
}
