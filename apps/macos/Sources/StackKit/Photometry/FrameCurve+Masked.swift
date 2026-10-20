extension FrameCurve {
  /// Below this many admitted pixels a masked measurement means nothing: the caller degrades to a
  /// no-op, never to a whole-frame curve (that is the different-sky mismatch the mask avoids).
  static let minMaskedSamples = 20_000

  /// The curve of the pixels `keep(x, y)` admits (`MeasureImageMasked`), strided down to
  /// `sampleLimit`; nil under `minMaskedSamples`.
  package static func masked(
    planes: [[Float]], width: Int, height: Int, keep: (Int, Int) -> Bool
  ) -> Self? {
    let plane = PhotomStats.sampleSlice(planes)
    guard !plane.isEmpty else { return nil }
    var accepted = 0
    for row in 0..<height {
      for column in 0..<width where keep(column, row) { accepted += 1 }
    }
    guard accepted >= minMaskedSamples else { return nil }
    let stride = max(1, accepted / sampleLimit)
    var sample: [Float] = []
    sample.reserveCapacity(accepted / stride + 1)
    var seen = 0
    for row in 0..<height {
      for column in 0..<width where keep(column, row) {
        if seen % stride == 0 { sample.append(plane[row * width + column]) }
        seen += 1
      }
    }
    return Self(sample: sample)
  }
}
