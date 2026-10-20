package import Foundation
internal import ImageKit

/// Repairs sensor-saturated cores before a multi-night stack (`transient/satmask.go`): after
/// photometric normalisation each night's clipped plateau lands at its own level, below the true
/// flux, and no rejection removes a coherent plateau. A saturated pixel takes the median of the
/// frames that still see it below their ceiling — when at least five do; a core clipped everywhere
/// has no true value to restore and is left alone.
///
/// Exact and memory-light: the saturated pixels are found frame by frame, only their values are
/// gathered, then each frame is rewritten — never the whole sequence in memory.
package enum SaturationRepair {
  /// Ceiling × margin is the detection threshold (flat division and resampling wobble the plateau).
  static let margin: Float = 0.90
  static let minimumCleanSamples = 5

  /// The repaired pixel count of each frame (`frames[i]` with ceiling `ceilings[i]`, 0 = disabled).
  package static func repair(_ frames: [URL], ceilings: [Float]) throws -> [Int] {
    let thresholds = frames.indices.map { $0 < ceilings.count && ceilings[$0] > 0 ? ceilings[$0] * margin : 0 }
    guard thresholds.contains(where: { $0 > 0 }) else { return frames.map { _ in 0 } }
    var saturated: [Set<Int>] = []
    for (index, url) in frames.enumerated() where thresholds[index] > 0 {
      try Task.checkCancellation()
      let planes = try FITSFile.read(at: url).image().planes
      if saturated.isEmpty { saturated = Array(repeating: [], count: planes.count) }
      for (channel, plane) in planes.enumerated() where channel < saturated.count {
        for (pixel, value) in plane.enumerated() where value >= thresholds[index] { saturated[channel].insert(pixel) }
      }
    }
    let medians = try cleanMedians(frames, thresholds: thresholds, saturated: saturated)
    return try frames.indices.map { index in
      try rewrite(frames[index], threshold: thresholds[index], medians: medians)
    }
  }

  /// Per channel, the upper median of the clean (0 < v < threshold) samples at each saturated pixel,
  /// where at least five frames give one (`cleanMedianPlanes`).
  static func cleanMedians(_ frames: [URL], thresholds: [Float], saturated: [Set<Int>]) throws -> [[Int: Float]] {
    let keys = saturated.map { Array($0).sorted() }
    var samples = keys.map { $0.map { _ in [Float]() } }
    for (index, url) in frames.enumerated() where thresholds[index] > 0 {
      try Task.checkCancellation()
      let planes = try FITSFile.read(at: url).image().planes
      for channel in keys.indices where channel < planes.count {
        for (slot, pixel) in keys[channel].enumerated() {
          let value = planes[channel][pixel]
          if value > 0 && value < thresholds[index] { samples[channel][slot].append(value) }
        }
      }
    }
    return keys.indices.map { channel in
      var medians: [Int: Float] = [:]
      for (slot, pixel) in keys[channel].enumerated() where samples[channel][slot].count >= minimumCleanSamples {
        let sorted = samples[channel][slot].sorted()
        medians[pixel] = sorted[sorted.count / 2]
      }
      return medians
    }
  }

  /// Replaces a frame's saturated pixels that have a clean median; rewrites it only when one did.
  static func rewrite(_ url: URL, threshold: Float, medians: [[Int: Float]]) throws -> Int {
    guard threshold > 0, medians.contains(where: { !$0.isEmpty }) else { return 0 }
    let file = try FITSFile.read(at: url)
    let image = try file.image()
    var repaired = 0
    for channel in image.planes.indices where channel < medians.count {
      for (pixel, median) in medians[channel] where image.planes[channel][pixel] >= threshold {
        image.planes[channel][pixel] = median
        repaired += 1
      }
    }
    if repaired > 0 { try file.write(image, to: url) }
    return repaired
  }
}
