/// The planes `EdgeTrim` reads, averaged per pixel: vignetting and coverage are colour-blind, and
/// averaging keeps one hot channel from deciding where the border is.
struct EdgeImage {
  let planes: [[Float]]
  let width: Int
  let height: Int

  /// The planes' mean at a pixel index, in float32 as the legacy sum.
  func mean(at index: Int) -> Float {
    var sum: Float = 0
    for plane in planes { sum += plane[index] }
    return sum / Float(planes.count)
  }

  /// The median of a 16-px sample of the middle half: the level everything is a fraction of.
  func interiorSky() -> Double {
    var sample: [Float] = []
    for y in stride(from: height / 4, to: 3 * height / 4, by: 16) {
      for x in stride(from: width / 4, to: 3 * width / 4, by: 16) {
        sample.append(mean(at: y * width + x))
      }
    }
    return EdgeLineStats.percentile(&sample, 0.5)
  }

  /// One `EdgeLineStats` entry per column (or row) of `rect`.
  ///
  /// Dead pixels are left out of the
  /// level and noise (a column 71% zeros has no meaningful median): `dead` reports them.
  func lineProfiles(_ rect: EdgeRect, columns: Bool, dead: Float) -> EdgeLineStats {
    let (count, across) = columns ? (rect.width, rect.height) : (rect.height, rect.width)
    var stats = EdgeLineStats(
      background: .init(repeating: 0, count: count), dead: .init(repeating: 0, count: count),
      noise: .init(repeating: 0, count: count))
    var live: [Float] = []
    live.reserveCapacity(across / EdgeTrim.lineSample + 1)
    for line in 0..<count {
      live.removeAll(keepingCapacity: true)
      var (deadCount, total) = (0, 0)
      for step in stride(from: 0, to: across, by: EdgeTrim.lineSample) {
        let (x, y) = columns ? (rect.x0 + line, rect.y0 + step) : (rect.x0 + step, rect.y0 + line)
        total += 1
        let value = mean(at: y * width + x)
        if value <= dead { deadCount += 1 } else { live.append(value) }
      }
      stats.dead[line] = Double(deadCount) / Double(max(1, total))
      stats.noise[line] = EdgeLineStats.lineNoise(live)
      stats.background[line] = EdgeLineStats.percentile(&live, EdgeTrim.linePercentile)
    }
    return stats
  }
}
