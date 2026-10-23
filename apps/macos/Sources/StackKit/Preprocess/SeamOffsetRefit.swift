package import Foundation
internal import ImageKit

/// Re-measures each night's sky against the anchor night's INSIDE their shared footprint and adds
/// the residual pedestal to the night's merged frames before the registration is applied
/// (`refitGroupOffsets`).
///
/// Whole-frame photometry compares different sky mixes when footprints rotate; its leftovers stack
/// into straight seams. Offset only; every guard is a reason, recorded.
package enum SeamOffsetRefit {
  /// One night's outcome (`SeamOffset`).
  package struct Record: Codable, Equatable, Sendable {
    package var session: String
    package var delta = 0.0
    package var applied = false
    /// Why the correction was skipped; empty when applied.
    package var reason = ""
  }

  static let epsilonSigma = 0.02
  static let maxBackgroundFraction = 0.5
  static let contaminationSigma = 0.5
  static let minimumOverlap = 0.25
  static let maxProbeFrames = 7

  /// Δ = anchor.bg − group.bg, or why the night is left alone (`seamOffsetDelta`).
  package static func delta(group: FrameCurve, anchor: FrameCurve) -> (
    delta: Double, reason: String
  ) {
    let background = anchor.background - group.background
    if abs(background) <= epsilonSigma * anchor.noise {
      return (0, "pedestal below stack visibility")
    }
    let low = anchor.quantiles[2] - group.quantiles[2]
    if abs(background - low) > contaminationSigma * anchor.noise {
      return (0, "overlap contaminated by extended signal (background and P20 deltas disagree)")
    }
    var cap = maxBackgroundFraction * anchor.background
    if cap <= 0 { cap = 3 * anchor.noise }
    if abs(background) > cap {
      return (
        0,
        "correction \(String(format: "%+.4g", background)) beyond the sanity cap "
          + "(\(String(format: "%.4g", cap)))"
      )
    }
    if group.background + background - 3 * group.noise < 0 {
      return (0, "correction would clip the group's sky below zero")
    }
    return (background, "")
  }

  /// Refits every night but the anchor; `frame(i)` is merged frame i's file.
  package static func refit(
    _ nights: [FrameSet], spans: [Range<Int>], anchor: Int, review: RegistrationReview,
    frameSize: (width: Int, height: Int), frame: @escaping (Int) -> URL
  ) throws -> [Record] {
    let (width, height) = frameSize
    guard spans.indices.contains(anchor), !review.frameHomographies.isEmpty else { return [] }
    let rejected = { (index: Int) in review.frameHomographies[index] == nil }
    let footprint = { (span: Range<Int>) in
      CoverageGrid.footprint(
        span, homographies: review.frameHomographies, rejected: rejected, frameWidth: width,
        frameHeight: height)
    }
    let anchorMask = footprint(spans[anchor])
    var records: [Record] = []
    for (index, night) in nights.enumerated() where index != anchor && index < spans.count {
      try Task.checkCancellation()
      var record = Record(session: night.key.session)
      let groupMask = footprint(spans[index])
      let overlap = zip(anchorMask, groupMask).map { $0 && $1 }
      let area = groupMask.count { $0 }
      let fraction = area == 0 ? 0 : Double(overlap.count { $0 }) / Double(area)
      if fraction < minimumOverlap {
        record.reason =
          "footprint overlap with the anchor too small (\(Int((fraction * 100).rounded()))%)"
      } else {
        let probe = Probe(
          review: review, overlap: overlap, width: width, height: height, frame: frame)
        record = try probe.measure(spans[index], against: spans[anchor], into: record)
      }
      records.append(record)
    }
    return records
  }
}
