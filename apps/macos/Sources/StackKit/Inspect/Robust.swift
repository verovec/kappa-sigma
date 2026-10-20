/// The small robust statistics channel detection uses (upper-middle order statistics).
enum Robust {
  static func median(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.sorted()[values.count / 2]
  }

  static func medianMAD(_ values: [Double]) -> (median: Double, mad: Double) {
    guard !values.isEmpty else { return (0, 0) }
    let center = median(values)
    return (center, median(values.map { abs($0 - center) }))
  }

  /// Scales to [0, 1]; a flat slice maps to 0.5 (no information).
  static func minMaxNormalized(_ values: [Double]) -> [Double] {
    guard let low = values.min(), let high = values.max() else { return [] }
    let span = high - low
    return values.map { span > 0 ? ($0 - low) / span : 0.5 }
  }
}
