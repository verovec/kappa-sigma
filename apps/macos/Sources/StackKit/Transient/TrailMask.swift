internal import Foundation

/// Removes satellite and aircraft trails, cosmic rays and hot pixels from REGISTERED frames before
/// they are stacked (`transient.MaskCrossFrameValidated`).
///
/// Per frame: (1) the blanket pass replaces every per-pixel positive outlier with the cross-frame
/// median; (2) the line pass paints the faint wings of each streak found on the frame's residual,
/// once validated window by window against the other frames, so walking noise is never
/// repainted; (3) reused sky tracks found on the mean residual are repaired where the frame
/// lights them; (4) streaks present in the median itself are repaired from the local sky.
/// Under five frames, or k ≤ 0, nothing runs. A frame is its planes, `frame[channel][pixel]`.
package enum TrailMask {
  /// Below this, the per-pixel median and MAD cannot separate a lone outlier.
  package static let minimumFrames = 5

  /// What every frame is judged against.
  struct Context {
    var median: [[Float]]
    var sigma: [[Float]]
    /// The whole sequence, or the streamed basis.
    var witnesses: Witnesses
    var medianSegments: [TrailSegment]
    var recurring: [RecurringCorridor]
    var k: Double
    var size: (width: Int, height: Int)
  }

  /// Masks `frames` in place; throws when a frame differs from the first in planes or size.
  package static func mask(_ frames: inout [[[Float]]], width: Int, height: Int, k: Double)
    async throws -> TrailMaskReport
  {
    guard frames.count >= minimumFrames, k > 0 else { return TrailMaskReport() }
    try checkShape(frames, pixels: width * height)
    let context = try await context(frames, width: width, height: height, k: k)
    var report = TrailMaskReport(
      geostationary: context.medianSegments.count, recurring: context.recurring.count)
    for index in frames.indices {
      try Task.checkCancellation()
      var frame = TrailMaskReport.Frame(index: index + 1)
      let own = OwnResidual(
        plane: context.witnesses.residuals[index], sky: context.witnesses.skies[index])
      maskFrame(&frames[index], own: own, skip: index, context: context, into: &frame)
      report.frames.append(frame)
    }
    return report
  }

  /// The statistics of `basis`: median and σ planes, residuals, sky noises, median and recurring
  /// streaks.
  static func context(_ basis: [TrailMaskPlanes.Frame], width: Int, height: Int, k: Double)
    async throws -> Context
  {
    let pixels = width * height
    let (median, sigma) = await TrailMaskPlanes.medianSigma(
      basis, channels: basis[0].count, pixels: pixels)
    try Task.checkCancellation()
    var mean = MeanResidual(pixels: pixels)
    let residuals = basis.map { frame in
      let residual = TrailMaskPlanes.residual(frame, median: median)
      mean.add(residual, frame: frame)
      return residual
    }
    let skies = residuals.map(TrailMaskPlanes.residualSky)
    let size = (width, height)
    let medianSegments = TrailMaskPlanes.medianTrails(median, width: width, height: height)
    let recurring = RecurringCorridor.find(
      mean: mean.plane, medianSegments: medianSegments,
      witnesses: Witnesses(residuals: residuals, skies: skies), k: k,
      size: size)
    return Context(
      median: median, sigma: sigma, witnesses: Witnesses(residuals: residuals, skies: skies),
      medianSegments: medianSegments, recurring: recurring, k: k, size: size)
  }

  /// The four passes on one frame; `own` is its residual taken before any pass, `skip` its
  /// position among the witnesses (−1 when it is not one).
  static func maskFrame(
    _ frame: inout TrailMaskPlanes.Frame, own: OwnResidual, skip: Int, context: Context,
    into record: inout TrailMaskReport.Frame
  ) {
    let size = context.size
    record.maskedPixels += TrailMaskPlanes.blanket(
      &frame, median: context.median, sigma: context.sigma, k: context.k)
    let candidates = TrailSegmentDetector.detect(
      own.plane, width: size.width, height: size.height, params: .residual(k: context.k))
    for candidate in candidates {
      guard
        let runs = TrailCorridor.validate(
          candidate, own: own, witnesses: context.witnesses, skip: skip, size: size,
          isZero: { TrailMaskPlanes.isZero(frame, $0) })
      else {
        record.rejected += 1
        continue
      }
      record.segments += 1
      for run in runs {
        for channel in frame.indices {
          record.maskedPixels += TrailSwath.paintMedian(
            &frame[channel], median: context.median[channel], width: size.width,
            height: size.height, segment: run)
        }
      }
    }
    for (index, corridor) in context.recurring.enumerated() {
      record.maskedPixels += corridor.repair(
        &frame, own: own, median: context.median, corridor: index, size: size)
    }
    for (index, segment) in context.medianSegments.enumerated() {
      for channel in frame.indices {
        record.maskedPixels += TrailSwath.paintLocalBackground(
          &frame[channel], width: size.width, height: size.height, segment: segment,
          seed: TrailMaskPlanes.seed(segment: index, channel: channel))
      }
    }
  }

  /// Registered frames share their plane count and size.
  static func checkShape(_ frames: [TrailMaskPlanes.Frame], pixels: Int) throws {
    let planes = frames[0].count
    for (index, frame) in frames.enumerated()
    where frame.count != planes || frame.contains(where: { $0.count != pixels }) {
      throw TrailMaskError.mismatchedFrame(index: index)
    }
  }
}
