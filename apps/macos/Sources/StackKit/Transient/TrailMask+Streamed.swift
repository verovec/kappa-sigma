package import Foundation
internal import ImageKit

extension TrailMask {
  /// `mask` under a memory budget (`transient.MaskCrossFrameStreamed`).
  ///
  /// Only `basis` evenly spaced frames are resident (their residuals feed the median, the
  /// validation and the mean); every frame is then read, masked and rewritten one at a time. A
  /// basis covering every frame reproduces `mask` bit for bit. Frames that change are rewritten in
  /// place, headers kept.
  package static func maskStreamed(_ urls: [URL], k: Double, basis: Int) async throws
    -> TrailMaskReport
  {
    guard urls.count >= minimumFrames, k > 0 else { return TrailMaskReport() }
    let indices = TrailMaskBudget.evenIndices(urls.count, max(basis, minimumFrames))
    let (context, shape) = try await streamContext(urls, basis: indices, k: k)
    let positions = Dictionary(uniqueKeysWithValues: indices.enumerated().map { ($1, $0) })
    var report = TrailMaskReport(
      geostationary: context.medianSegments.count, recurring: context.recurring.count)
    for (index, url) in urls.enumerated() {
      try Task.checkCancellation()
      let file = try FITSFile.read(at: url)
      let image = try file.image()
      var frame = image.planes
      guard frame.count == shape.planes, image.width == shape.width, image.height == shape.height
      else { throw TrailMaskError.mismatchedFrame(index: index) }
      // The residual is taken before the blanket pass flattens the streak's core.
      let own = TrailMaskPlanes.residual(frame, median: context.median)
      var record = TrailMaskReport.Frame(index: index + 1)
      maskFrame(
        &frame, own: OwnResidual(plane: own, sky: TrailMaskPlanes.residualSky(own)),
        skip: positions[index] ?? -1, context: context, into: &record)
      report.frames.append(record)
      if record.maskedPixels > 0 {
        image.planes = frame
        try file.write(image, to: url)
      }
    }
    return report
  }

  /// The basis frames' context; their pixels are released once their residuals are taken.
  private static func streamContext(_ urls: [URL], basis: [Int], k: Double) async throws -> (
    Context, (planes: Int, width: Int, height: Int)
  ) {
    var frames: [TrailMaskPlanes.Frame] = []
    var size = (width: 0, height: 0)
    for index in basis {
      try Task.checkCancellation()
      let image = try FITSFile.read(at: urls[index]).image()
      if frames.isEmpty { size = (image.width, image.height) }
      frames.append(image.planes)
    }
    try checkShape(frames, pixels: size.width * size.height)
    let shape = (frames[0].count, size.width, size.height)
    return (try await context(frames, width: size.width, height: size.height, k: k), shape)
  }
}
