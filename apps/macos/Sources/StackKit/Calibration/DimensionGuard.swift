internal import Foundation
internal import ImageKit

/// Keeps a master shot on another sensor away from Siril (`calib/dims.go`).
///
/// Siril does not fail on a wrong-size master: `calibrate` logs "Images must have same
/// dimensions.", skips the correction and exits 0, so the lights are stacked raw while the notes
/// say the master was applied. The filtering runs on the candidate POOL, not the finished
/// selection, so the matcher's fallbacks can still reach the next-best master.
package enum DimensionGuard {
  /// The masters whose pixel size equals the light's, and a note naming what was excluded.
  ///
  /// A master whose size cannot be read is KEPT (a master still to be built has no file); an
  /// unreadable light leaves the pool untouched.
  package static func keepMatching(
    _ masters: [CalibrationMaster], lightPath: String
  ) -> (masters: [CalibrationMaster], note: String?) {
    guard let light = dimensions(lightPath) else { return (masters, nil) }
    var kept: [CalibrationMaster] = []
    var dropped: [String: Int] = [:]
    for master in masters {
      guard let size = dimensions(master.path), size != light else {
        kept.append(master)
        continue
      }
      dropped["\(size.width)×\(size.height)", default: 0] += 1
    }
    guard !dropped.isEmpty else { return (kept, nil) }
    let sizes = dropped.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
      .map { $0.value > 1 ? "\($0.key) (×\($0.value))" : $0.key }
    return (
      kept,
      "\(dropped.values.reduce(0, +)) calibration master(s) from another sensor "
        + "(\(sizes.joined(separator: ", "))) were not considered — these lights are "
        + "\(light.width)×\(light.height)"
    )
  }

  /// Whether two files share their pixel size (`SameDims`); `same` means nothing unless `known`
  /// (both headers read).
  package static func sameDimensions(_ lhs: String, _ rhs: String) -> (same: Bool, known: Bool) {
    guard let left = dimensions(lhs), let right = dimensions(rhs) else { return (false, false) }
    return (left == right, true)
  }

  struct Size: Equatable {
    var width: Int
    var height: Int
  }

  /// NAXIS1 × NAXIS2 from the header alone; `nil` for a missing, non-FITS or sizeless file.
  static func dimensions(_ path: String) -> Size? {
    guard !path.isEmpty, let file = try? FITSFile.read(at: URL(fileURLWithPath: path)),
      let width = file.header.int("NAXIS1"), let height = file.header.int("NAXIS2"),
      width > 0, height > 0
    else { return nil }
    return Size(width: width, height: height)
  }
}
