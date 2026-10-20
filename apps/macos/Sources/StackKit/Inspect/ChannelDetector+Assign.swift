extension ChannelDetector {
  /// Step 0 (same filter again: an over-split run) and each skipped filter cost this much.
  static let stayPenalty = 0.20
  static let skipPenalty = 0.40

  /// Labels each run by the minimum-cost forward walk through the cyclic order (`assignCyclic`).
  static func assignCyclic(
    _ samples: [Sample], runs: [[Int]], order: [String]
  ) -> (filters: [String], confidence: [Double], overall: Double) {
    guard !runs.isEmpty else { return ([], [], 0) }
    let levels = runs.map { members in
      members.reduce(0) { $0 + samples[$1].fingerprint.level } / Double(members.count)
    }
    let richness = runs.map { members in
      members.reduce(0) { $0 + samples[$1].fingerprint.starRichness } / Double(members.count)
    }
    let normalizedLevels = Robust.minMaxNormalized(levels)
    let normalizedRichness = Robust.minMaxNormalized(richness)
    let costs = runs.indices.map { run in
      order.map { emission($0, level: normalizedLevels[run], richness: normalizedRichness[run]) }
    }
    let path = viterbi(costs, order: order)
    return (path.filters, path.confidence, overallConfidence(levels, averageEmission: path.average))
  }

  /// How a flat set with no L/Ha anchor scores low and is surfaced for override.
  private static func overallConfidence(_ levels: [Double], averageEmission: Double) -> Double {
    guard let low = levels.min(), let high = levels.max() else { return 0 }
    let spread = high > 0 ? (high - low) / high : 0
    return max(0, min(1, spread)) * max(0, 1 - 2 * averageEmission)
  }

  /// How badly a run fits a filter from its normalized brightness and star richness.
  ///
  /// A faint run is cheaply narrowband only when stars are absent too.
  package static func emission(_ filter: String, level: Double, richness: Double) -> Double {
    let score = 0.5 * level + 0.5 * richness
    if filter == "L" { return 1 - score }
    if Filter.isNarrowband(filter) { return score + max(0, richness - 0.5) }
    return max(score, 1 - score) - 0.5
  }

  /// The forward cyclic DP: min-cost filter path, per-run confidence, average emission.
  private static func viterbi(
    _ costs: [[Double]], order: [String]
  ) -> (filters: [String], confidence: [Double], average: Double) {
    let positions = order.count
    var table = [costs[0]]
    var back = [[Int](repeating: 0, count: positions)]
    for run in 1..<costs.count {
      var row = [Double](repeating: 0, count: positions)
      var from = [Int](repeating: 0, count: positions)
      for position in 0..<positions {
        var best = Double.infinity
        for previous in 0..<positions {
          let step = ((position - previous) % positions + positions) % positions
          let cost = table[run - 1][previous] + transitionCost(step)
          if cost < best {
            best = cost
            from[position] = previous
          }
        }
        row[position] = best + costs[run][position]
      }
      table.append(row)
      back.append(from)
    }
    var position = 0
    var best = Double.infinity
    for (candidate, cost) in table[costs.count - 1].enumerated() where cost < best {
      best = cost
      position = candidate
    }
    var filters = [String](repeating: "", count: costs.count)
    var confidence = [Double](repeating: 0, count: costs.count)
    var total = 0.0
    for run in stride(from: costs.count - 1, through: 0, by: -1) {
      filters[run] = order[position]
      confidence[run] = max(0, 1 - costs[run][position])
      total += costs[run][position]
      if run > 0 { position = back[run][position] }
    }
    return (filters, confidence, total / Double(costs.count))
  }

  /// Advancing exactly one position is free; staying or skipping costs.
  private static func transitionCost(_ step: Int) -> Double {
    switch step {
    case 1: 0
    case 0: stayPenalty
    default: Double(step - 1) * skipPenalty
    }
  }
}
