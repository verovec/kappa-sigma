/// The ragged edge a registered stack carries, measured on the finished master
/// (`internal/pipeline/edgecrop.go`) so it never reaches a sky model.
///
/// A line is border when it still holds pixels no frame covered (DEAD), or when its background
/// sits off the fitted trend by more than a few sigma AND its own noise is well above the
/// interior's (SKIRT: fewer frames reached it). The noise clause is what keeps a nebula running
/// off the frame: it is off-level too, but as deep as the rest of the stack.
package enum EdgeTrim {
  /// A pixel below this fraction of the interior sky received no data.
  static let deadLevel = 0.05
  /// A line with more than this share of dead pixels is still inside the border.
  static let deadFraction = 0.002
  /// How far (in line-to-line sigma) a background may sit off the trend before it reads as skirt.
  static let sigma = 5.0
  /// How much noisier than the interior a line must be to corroborate the level test.
  static let noiseRatio = 1.3
  /// Consecutive interior-like lines needed to call the border over (the skirt is not monotonic).
  static let stableLines = 32
  /// Never cut more than this off one side of the original frame.
  package static let maxTrimFraction = 0.12
  /// Subsampling across each line.
  static let lineSample = 4
  /// The per-line background statistic: the median (a low percentile under-reads the skirt).
  static let linePercentile = 0.50
  /// A profile shorter than this cannot support a trend fit plus a stable run.
  static let minProfile = 4 * stableLines

  /// The largest rectangle free of the stack's edge, and whether a side hit the cap (the result
  /// is then a floor, not the answer).
  ///
  /// Columns and rows are measured alternately, twice: the
  /// uncovered region is a wedge, so trimming one changes what the other sees.
  package static func measure(_ planes: [[Float]], width: Int, height: Int) -> (
    rect: EdgeRect, capped: Bool
  ) {
    var rect = EdgeRect(x0: 0, y0: 0, x1: width, y1: height)
    guard width >= minProfile, height >= minProfile, !planes.isEmpty else { return (rect, false) }
    let image = EdgeImage(planes: planes, width: width, height: height)
    let dead = Float(deadLevel * image.interiorSky())
    let (maxX, maxY) = (Int(maxTrimFraction * Double(width)), Int(maxTrimFraction * Double(height)))
    var capped = false
    for _ in 0..<2 {
      for columns in [true, false] {
        let stats = image.lineProfiles(rect, columns: columns, dead: dead)
        guard let trend = EdgeTrend(stats.background) else { continue }
        // The cap is a budget per SIDE of the original frame, not per pass.
        let budget =
          columns
          ? (maxX - rect.x0, maxX - (width - rect.x1)) : (maxY - rect.y0, maxY - (height - rect.y1))
        let (low, high, hit) = trimEnds(stats, trend: trend, budget: budget)
        capped = capped || hit
        if columns {
          (rect.x0, rect.x1) = (rect.x0 + low, rect.x1 - high)
        } else {
          (rect.y0, rect.y1) = (rect.y0 + low, rect.y1 - high)
        }
      }
    }
    return (rect, capped)
  }

  /// How many lines each end of a profile gives up, and whether either hit its budget.
  static func trimEnds(
    _ stats: EdgeLineStats, trend: EdgeTrend, budget: (Int, Int)
  ) -> (low: Int, high: Int, capped: Bool) {
    let reference = EdgeLineStats.interiorNoise(stats.noise)
    let border = { (index: Int) -> Bool in
      if stats.dead[index] > deadFraction || stats.background[index].isNaN { return true }
      if abs(stats.background[index] - trend.value(at: index)) <= sigma * trend.scale {
        return false
      }
      // Off-level is not enough: only the stack's own shallow edge is also noisier.
      return reference <= 0 || stats.noise[index].isNaN
        || stats.noise[index] > noiseRatio * reference
    }
    let count = stats.background.count
    var low = walkIn(count, border) { $0 }
    var high = walkIn(count, border) { count - 1 - $0 }
    var capped = false
    if low > max(0, budget.0) { (low, capped) = (max(0, budget.0), true) }
    if high > max(0, budget.1) { (high, capped) = (max(0, budget.1), true) }
    // Pathological: keep the field and let the cap flag say so.
    if low + high >= count { return (0, 0, true) }
    return (low, high, capped)
  }

  /// The leading border lines in the order at(0), at(1)…: the count stops at the start of the
  /// first run of `stableLines` interior lines, so a lone clean line in the skirt does not end it.
  static func walkIn(_ count: Int, _ border: (Int) -> Bool, at: (Int) -> Int) -> Int {
    var (trim, good) = (0, 0)
    for step in 0..<count {
      if border(at(step)) {
        (good, trim) = (0, step + 1)
        continue
      }
      good += 1
      if good >= stableLines { break }
    }
    return trim
  }
}
