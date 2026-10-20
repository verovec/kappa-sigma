/// The estimators behind `FrameCurve` (`imgops.Percentile`, `Subsample`, `photom.mad`), with the
/// legacy arithmetic: percentiles in double with linear interpolation (fused, as Go fuses
/// `a + f·(b − a)` on arm64), deviations in float32, medians averaging the two middle values.
enum PhotomStats {
  /// The p-th percentile of an ascending array (`imgops.Percentile`): rank p/100·(n−1), linear
  /// interpolation between its neighbours; 0 when empty.
  static func percentile(sorted values: [Double], _ percent: Double) -> Double {
    guard let first = values.first, let last = values.last else { return 0 }
    if percent <= 0 { return first }
    if percent >= 100 { return last }
    let rank = percent / 100 * Double(values.count - 1)
    let low = Int(rank.rounded(.down))
    guard low + 1 < values.count else { return last }
    let fraction = rank - Double(low)
    return values[low].addingProduct(fraction, values[low + 1] - values[low])
  }

  /// The percentile of float samples (sorted in double, as the legacy copy did).
  static func percentile(_ values: [Float], _ percent: Double) -> Double {
    percentile(sorted: values.map(Double.init).sorted(), percent)
  }

  /// At most `limit` evenly strided samples; the input itself when it already fits (`Subsample`).
  static func subsample(_ values: [Float], limit: Int) -> [Float] {
    guard limit > 0, values.count > limit else { return values }
    return Array(stride(from: 0, to: values.count, by: values.count / limit).map { values[$0] })
  }

  /// median(|x − median(x)|), the deviations rounded to float32 (`photom.mad`).
  static func mad(_ values: [Float]) -> Double {
    guard !values.isEmpty else { return 0 }
    let center = percentile(values, 50)
    return percentile(values.map { Float(abs(Double($0) - center)) }, 50)
  }

  /// Plane 0, or the per-pixel float32 mean of the first three planes (`sampleSlice`).
  static func sampleSlice(_ planes: [[Float]]) -> [Float] {
    guard let first = planes.first else { return [] }
    guard planes.count > 1 else { return first }
    let used = planes.prefix(3)
    var sum = [Float](repeating: 0, count: first.count)
    for plane in used {
      for index in sum.indices where index < plane.count { sum[index] += plane[index] }
    }
    let inverse = Float(1) / Float(used.count)
    return sum.map { $0 * inverse }
  }

  /// The median; the mean of the two middle values for an even count; 0 when empty (`medianFloat`).
  static func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : 0.5 * (sorted[middle - 1] + sorted[middle])
  }
}
