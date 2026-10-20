internal import Accelerate

/// The full-resolution statistics of a layer (`LinearBundle.Stats`), by vDSP sorts.
enum LayerStats {
  /// Stats of `planes` averaged per pixel; non-finite pixels are left out.
  static func measure(_ planes: [[Float]]) -> LinearBundle.Stats {
    var values = mean(planes).filter(\.isFinite)
    guard !values.isEmpty else { return LinearBundle.Stats(bg: 0, madn: 0, sky: 0, snr: 0) }
    vDSP.sort(&values, sortOrder: .ascending)
    let median = values[values.count / 2]
    var deviations = vDSP.absolute(vDSP.add(-median, values))
    vDSP.sort(&deviations, sortOrder: .ascending)
    let madn = 1.4826 * Double(deviations[deviations.count / 2])
    // `values` is sorted: the sky is the median of the prefix at most 3 MADN above the median.
    let ceiling = Float(Double(median) + 3 * madn)
    let kept = values.partitioningIndex { $0 > ceiling }
    let sky = Double(values[max(0, kept - 1) / 2])
    let bg = Double(median)
    return LinearBundle.Stats(bg: bg, madn: madn, sky: sky, snr: madn > 0 ? bg / madn : 0)
  }

  /// The per-pixel mean of the planes.
  private static func mean(_ planes: [[Float]]) -> [Float] {
    guard var sum = planes.first else { return [] }
    for plane in planes.dropFirst() { sum = vDSP.add(sum, plane) }
    return planes.count == 1 ? sum : vDSP.divide(sum, Float(planes.count))
  }
}

extension Array where Element == Float {
  /// The first index whose element satisfies `predicate`, the array being partitioned by it.
  fileprivate func partitioningIndex(where predicate: (Float) -> Bool) -> Int {
    var (low, high) = (startIndex, endIndex)
    while low < high {
      let middle = (low + high) / 2
      if predicate(self[middle]) { high = middle } else { low = middle + 1 }
    }
    return low
  }
}
