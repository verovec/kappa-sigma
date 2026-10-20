/// What one scan of an image reduces each line to (`lineStats`): its background level, the share
/// of its pixels no frame covered, and its pixel-to-pixel noise (the depth proxy).
struct EdgeLineStats {
  var background: [Double]
  var dead: [Double]
  var noise: [Double]

  /// The reference the per-line noise is compared against: the median over the middle 60% of the
  /// profile, where the stack is at full depth; 0 when nothing there is measurable.
  static func interiorNoise(_ noise: [Double]) -> Double {
    let count = noise.count
    let middle = (count / 5..<4 * count / 5).map { noise[$0] }.filter { !$0.isNaN }.sorted()
    return middle.isEmpty ? 0 : middle[middle.count / 2]
  }

  /// The noise of a line from the MAD of its successive differences (structure-blind: a gradient
  /// or an object crossing the line does not inflate it); NaN under 16 values.
  static func lineNoise(_ values: [Float]) -> Double {
    guard values.count >= 16 else { return .nan }
    var differences = (1..<values.count).map { abs(values[$0] - values[$0 - 1]) }
    return percentile(&differences, 0.5) * 1.4826 / 2.0.squareRoot()
  }

  /// The p-quantile at index ⌊p·(n−1)⌋ of `values`, sorted in place; NaN when empty.
  static func percentile(_ values: inout [Float], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    values.sort()
    return Double(values[Int(fraction * Double(values.count - 1))])
  }
}
