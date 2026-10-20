/// The probe's answer; `unknown` is a genuine third state that keeps today's behaviour.
package enum CFAVerdict: Sendable {
  case cfa
  case mono
  case unknown
}

/// Is a frame really a colour mosaic? Answered from the pixels, not the FILTER card
/// (`internal/inspect/cfaprobe.go`): under four dyes the sub-lattices split by tens of percent
/// with the two greens together; one mono sensor differs only by noise.
package enum CFAProbe {
  /// Colour split (R vs B vs the green pair) above which the frame is a mosaic.
  static let minColorSplit = 0.03
  /// Split below which the four sub-lattices are one response.
  static let maxFlatSplit = 0.012
  /// The greens may differ by at most this share of the colour split.
  static let maxGreenSplit = 0.5
  static let sampleFrames = 3

  /// One frame: a single plane of at least one 2×2 cell.
  package static func verdict(_ image: PixelPlanes) -> CFAVerdict {
    guard image.planes.count == 1, image.width >= 2, image.height >= 2,
      let means = subLatticeMeans(image.planes[0], width: image.width, height: image.height)
    else { return .unknown }
    // In every pattern the greens are the (1,0)/(0,1) diagonal, R and B the other one.
    let green = (means.m10 + means.m01) / 2
    let mean = (means.m00 + means.m10 + means.m01 + means.m11) / 4
    guard mean > 0 else { return .unknown }
    let values = [means.m00, green, means.m11]
    let colorSplit = ((values.max() ?? 0) - (values.min() ?? 0)) / mean
    let greenSplit = abs(means.m10 - means.m01) / mean
    if colorSplit >= minColorSplit && greenSplit <= colorSplit * maxGreenSplit { return .cfa }
    if colorSplit <= maxFlatSplit { return .mono }
    return .unknown
  }

  /// A bounded sample that must AGREE: one frame is a weak witness and a wrong verdict destroys
  /// a session. Anything unreadable is not evidence.
  package static func verdict(_ frames: [CaptureFrame], pixels: PixelReader) -> CFAVerdict {
    var verdict = CFAVerdict.unknown
    for frame in FilterSetClassifier.sample(frames, count: sampleFrames) {
      guard let image = try? pixels.planes(frame.path) else { return .unknown }
      let current = Self.verdict(image)
      if current == .unknown || (verdict != .unknown && current != verdict) { return .unknown }
      verdict = current
    }
    return verdict
  }

  private static func subLatticeMeans(
    _ pixels: [Float], width: Int, height: Int
  ) -> (m00: Double, m10: Double, m01: Double, m11: Double)? {
    guard pixels.count >= width * height else { return nil }
    var sums = [0.0, 0.0, 0.0, 0.0]
    var count = 0
    for y in stride(from: 0, to: height - 1, by: 2) {
      for x in stride(from: 0, to: width - 1, by: 2) {
        sums[0] += Double(pixels[y * width + x])
        sums[1] += Double(pixels[y * width + x + 1])
        sums[2] += Double(pixels[(y + 1) * width + x])
        sums[3] += Double(pixels[(y + 1) * width + x + 1])
        count += 1
      }
    }
    guard count > 0 else { return nil }
    let total = Double(count)
    return (sums[0] / total, sums[1] / total, sums[2] / total, sums[3] / total)
  }
}
