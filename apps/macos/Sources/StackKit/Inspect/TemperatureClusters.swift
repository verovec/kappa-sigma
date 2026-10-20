/// Temperature decided for the GROUP, not the frame (`clusterByTemperature`).
///
/// A fixed 5 °C grid has hard edges: a cooler regulating at −9.8 with excursions landed on both
/// sides of −7.5 and −12.5, and the one-or-two-frame stragglers were lost. Instead: sort the
/// members, cut only at a real gap, cap the span, label each cluster with its median.
enum TemperatureClusters {
  /// A consecutive jump above this starts a new set (°C).
  static let gapC = 3.0
  /// One set never spans more than this (°C): a −20 dark must not average into a −10 master.
  static let spanC = 5.0
  /// A run this small cannot build a master; the span cap's fence-post stragglers rejoin.
  static let stragglerMaxFrames = 2

  struct Cluster {
    var indices: [Int]
    var bucketC: Int
  }

  /// Splits the frames at `indices` of `frames` (one group) into clusters. Types without a
  /// temperature stay one cluster at bucket 0; frames with no temperature form their own.
  static func split(_ indices: [Int], of frames: [CaptureFrame], type: FrameType) -> [Cluster] {
    guard type.usesTemperature else { return [Cluster(indices: indices, bucketC: 0)] }
    let without = indices.filter { !frames[$0].hasTemp }
    let byTemp = indices.filter { frames[$0].hasTemp }
      .enumerated().sorted { lhs, rhs in
        let (left, right) = (frames[lhs.element].tempMilliC, frames[rhs.element].tempMilliC)
        return left != right ? left < right : lhs.offset < rhs.offset
      }
      .map(\.element)
    var out = without.isEmpty ? [] : [Cluster(indices: without, bucketC: 0)]
    guard !byTemp.isEmpty else { return out }
    let celsius = { (index: Int) in frames[index].tempC }
    for run in rejoinStragglers(runs(byTemp, celsius: celsius), celsius: celsius) {
      let median = celsius(run[run.count / 2])
      let ordered = run.enumerated().sorted { lhs, rhs in
        let (left, right) = (frames[lhs.element].path, frames[rhs.element].path)
        return left != right ? left < right : lhs.offset < rhs.offset
      }
      out.append(Cluster(indices: ordered.map(\.element), bucketC: Int(median.rounded())))
    }
    return out
  }

  /// Temperature-sorted indices cut where the gap or the span is exceeded.
  private static func runs(_ sorted: [Int], celsius: (Int) -> Double) -> [[Int]] {
    var runs: [[Int]] = []
    var start = 0
    for index in 1...sorted.count {
      if index < sorted.count {
        let gap = celsius(sorted[index]) - celsius(sorted[index - 1])
        let span = celsius(sorted[index]) - celsius(sorted[start])
        if gap <= gapC && span <= spanC { continue }
      }
      runs.append(Array(sorted[start..<index]))
      start = index
    }
    return runs
  }

  /// Folds a ≤ 2-frame run into its nearest neighbour when the edge gap is within `gapC` — the
  /// signature of a span-cap fence-post, not a new thermal regime (`rejoinSpanStragglers`).
  private static func rejoinStragglers(_ input: [[Int]], celsius: (Int) -> Double) -> [[Int]] {
    var runs = input
    var changed = true
    while changed {
      changed = false
      for index in runs.indices where runs[index].count <= stragglerMaxFrames && runs.count > 1 {
        let run = runs[index]
        let previousGap =
          index > 0 ? celsius(run[0]) - celsius(runs[index - 1][runs[index - 1].count - 1]) : .infinity
        let nextGap =
          index + 1 < runs.count ? celsius(runs[index + 1][0]) - celsius(run[run.count - 1]) : .infinity
        if previousGap <= gapC && previousGap <= nextGap {
          runs[index - 1] += run
        } else if nextGap <= gapC {
          runs[index + 1] = run + runs[index + 1]
        } else {
          continue
        }
        runs.remove(at: index)
        changed = true
        break
      }
    }
    return runs
  }
}
