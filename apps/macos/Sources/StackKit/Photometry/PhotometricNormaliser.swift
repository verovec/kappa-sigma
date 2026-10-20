internal import Foundation
internal import ImageKit

/// Maps every night onto the reference night's photometric scale (`photom.NormalizeGroups`).
///
/// Each group is measured on up to seven evenly spaced frames, fitted onto the reference's median
/// curve, degraded if the fit would clip its sky below zero, and — unless it is the reference or
/// close to identity — rewritten in place as `scale · p + offset`. Soft-fail: an unreadable frame,
/// a group that is not float32, or cancellation is a note and leaves the frames as they were.
package enum PhotometricNormaliser {
  static let maxProbeFrames = 7
  /// A group gets a saturation note above this fraction (~150 px of a 16 MP frame).
  static let saturationNoteFraction = 1e-5

  /// One record per group, and the notes.
  package static func normalise(_ groups: [PhotomGroup]) -> (records: [PhotomGroupRecord], notes: [String]) {
    guard !groups.isEmpty else { return ([], []) }
    let referenceIndex = reference(groups)
    let reference = groups[referenceIndex]
    var notes: [String] = []
    guard let curve = referenceCurve(reference, notes: &notes) else {
      return (groups.map(PhotomGroupRecord.init(skipping:)), notes)
    }
    var records: [PhotomGroupRecord] = []
    for (index, group) in groups.enumerated() {
      if Task.isCancelled {
        notes.append("photometric normalization cancelled")
        return (records + groups[index...].map(PhotomGroupRecord.init(skipping:)), notes)
      }
      records.append(
        normalise(group, onto: curve, referenceMeta: reference.meta, isReference: index == referenceIndex, notes: &notes))
    }
    return (records, notes)
  }

  /// The first group flagged as reference, else the one with the most frames (`pickReference`).
  static func reference(_ groups: [PhotomGroup]) -> Int {
    if let flagged = groups.firstIndex(where: \.isReference) { return flagged }
    var best = 0
    for (index, group) in groups.enumerated() where group.paths.count > groups[best].paths.count {
      best = index
    }
    return best
  }

  /// The component-wise median of the reference's probe frames; nil when none is readable.
  static func referenceCurve(_ group: PhotomGroup, notes: inout [String]) -> FrameCurve? {
    var curves: [FrameCurve] = []
    for path in evenSpaced(group.paths, maxProbeFrames) {
      guard let curve = try? measure(path) else {
        notes.append("photometric reference \"\(group.label)\": unreadable frame \(path)")
        continue
      }
      curves.append(curve)
    }
    guard !curves.isEmpty else {
      notes.append("photometric reference \"\(group.label)\": no readable frames — normalization skipped")
      return nil
    }
    return FrameCurve.median(curves)
  }

  /// The curve of a FITS file.
  package static func measure(_ path: String) throws -> FrameCurve {
    FrameCurve(planes: try FITSFile.read(at: URL(fileURLWithPath: path)).image().planes)
  }

  /// At most `count` evenly strided paths (`evenSpaced`).
  static func evenSpaced(_ paths: [String], _ count: Int) -> [String] {
    guard count > 0, paths.count > count else { return paths }
    return Array(stride(from: 0, to: paths.count, by: paths.count / count).map { paths[$0] }.prefix(count))
  }
}
