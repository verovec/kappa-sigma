package import Foundation
internal import ImageKit

/// Fades the noise-depth step at coverage boundaries on a multi-night master, in place
/// (`equalizeSeamNoise`): one starlet pass whose per-pixel strength is the excess noise factor of
/// the coverage — zero, byte for byte, in the full-depth core.
package enum SeamNoiseEqualiser {
  /// What the pass did (`SeamNoiseEq`).
  package struct Record: Equatable, Sendable {
    package var depthMin = 0
    package var depthMax = 0
    package var weightMax = 0.0
    package var sigmaBefore = 0.0
    package var sigmaAfter = 0.0
    package var applied = false
    package var reason = ""
    /// `luminance` for a colour master (chroma kept), `mono` for one plane.
    package var mode = ""
  }

  /// The treatment of a master with `planes` planes.
  package static func mode(planes: Int) -> String { planes == 3 ? "luminance" : "mono" }

  /// Equalises the master at `url` with `grid`; soft-fails, with the reason, leaving it untouched.
  package static func equalise(_ url: URL, grid: CoverageGrid) -> Record {
    var record = Record()
    guard !Task.isCancelled else {
      record.reason = "cancelled"
      return record
    }
    do {
      let file = try FITSFile.read(at: url)
      let image = try file.image()
      let (weights, reason) = SeamNoiseWeights.weights(
        grid, width: image.width, height: image.height)
      guard let weights else {
        record.reason = reason
        return record
      }
      let covered = grid.counts.filter { $0 > 0 }
      record.depthMin = Int(covered.min() ?? 0)
      record.depthMax = Int(covered.max() ?? 0)
      record.weightMax = Double(weights.max() ?? 0)
      record.mode = mode(planes: image.planes.count)
      record.sigmaBefore = StarletDenoiser.measure(
        image.planes[0], width: image.width, height: image.height)
      var planes = image.planes
      StarletDenoiser.denoise(&planes, width: image.width, height: image.height, weights: weights)
      image.planes = planes
      try file.write(image, to: url)
      record.sigmaAfter = StarletDenoiser.measure(
        image.planes[0], width: image.width, height: image.height)
      record.applied = true
    } catch {
      record.reason = "seam noise equalization: \(ChannelStacker.describe(error))"
    }
    return record
  }
}
