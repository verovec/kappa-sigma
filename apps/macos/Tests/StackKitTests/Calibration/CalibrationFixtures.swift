import StackKit

/// Builders shared by the calibration tests, mirroring the Go test helpers (`masters()`,
/// `light(...)`, `calSet(...)`, `oscFlat(...)`).
enum CalibrationFixtures {
  static func master(
    _ type: MasterType, path: String, filter: String = "", exposureMs: Int = 0, gain: Int = 139,
    offset: Int = 21, bin: Int = 1, tempC: Int? = nil, frames: Int = 0, session: String = "",
    filterSet: FilterSet = .unknown, fromLibrary: Bool = false
  ) -> CalibrationMaster {
    var master = CalibrationMaster(type: type, path: path)
    master.filter = filter
    master.exposureMs = exposureMs
    master.gain = gain
    master.offset = offset
    master.bin = bin
    if let tempC {
      master.tempMilliC = tempC * 1000
      master.hasTemp = true
    }
    master.frameCount = frames
    master.session = session
    master.filterSet = filterSet
    master.fromLibrary = fromLibrary
    return master
  }

  /// `masters()` of match_test.go.
  static let standard: [CalibrationMaster] = [
    master(.bias, path: "bias.fits", frames: 8),
    master(.dark, path: "dark120.fits", exposureMs: 120_000, tempC: -15, frames: 5),
    master(.dark, path: "dark300.fits", exposureMs: 300_000, tempC: -15, frames: 5),
    master(.flat, path: "flatL.fits", filter: "L", exposureMs: 2000, frames: 4),
  ]

  /// `library()` of library_test.go.
  static let library: [CalibrationMaster] = [
    master(.bias, path: "bias.fits", frames: 8),
    master(.dark, path: "dark.fits", exposureMs: 120_000, tempC: -15, frames: 5),
    master(.flat, path: "flatL.fits", filter: "L", exposureMs: 2000, frames: 4),
  ]

  /// A light set key (`light(filter, exp, gain, tempC)` of match_test.go).
  static func light(
    _ filter: String, exposureMs: Int, gain: Int = 139, offset: Int = 21, tempC: Int = 0,
    session: String = "", color: Bool = false
  ) -> SetKey {
    SetKey(
      type: .light, filter: filter, exposureMs: exposureMs, gain: gain, offset: offset,
      tempBucketC: tempC, bin: 1, session: session, color: color)
  }

  /// A calibration set of `count` placeholder frames, keyed the way inspect keys it.
  static func set(_ key: SetKey, count: Int = 1, paths: [String] = []) -> FrameSet {
    let names =
      paths.isEmpty ? (0..<count).map { "/frames/\(key.type.rawValue)_\($0).fits" } : paths
    let frames = names.map { CaptureFrame(path: $0) }
    return FrameSet(key: key, frames: frames, indices: Array(frames.indices))
  }

  /// `calSet(t, filter, exp, gain, tempC)` of library_test.go (offset 21, bin 1).
  static func calibrationKey(
    _ type: FrameType, filter: String = "", exposureMs: Int = 0, gain: Int = 139, offset: Int = 21,
    tempC: Int = 0, session: String = ""
  ) -> SetKey {
    SetKey(
      type: type, filter: filter, exposureMs: exposureMs, gain: gain, offset: offset,
      tempBucketC: tempC, bin: 1, session: session)
  }

  static func notes(_ selection: CalibrationSelection, contain text: String) -> Bool {
    selection.notes.contains { $0.contains(text) }
  }
}
