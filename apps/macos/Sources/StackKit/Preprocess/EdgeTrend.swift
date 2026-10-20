/// A sigma-clipped quadratic over a whole line profile and the robust scale of its residuals
/// (`interiorTrend`): a genuine sky gradient is followed, so only a departure from it counts.
///
/// Clipped, so the skirt drops out after one pass; spanning the WHOLE profile, so the trend is
/// never extrapolated to the edges (a galaxy tilting a middle-only fit sends its extrapolation
/// twelve sigma off at the corners).
struct EdgeTrend {
  /// c0 + c1·u + c2·u², u ∈ [−1, 1) across the profile.
  let coefficients: [Double]
  let count: Int
  /// 1.4826 · MAD of the kept residuals, floored at 1e-6 of the level.
  let scale: Double

  /// The fit, or nil when too few usable lines remain to fit or the residuals have no scale.
  init?(_ background: [Double]) {
    let count = background.count
    var keep = background.map { !$0.isNaN }
    var pass = 0
    while true {
      let fitted = keep.count { $0 }
      guard fitted >= 3 * EdgeTrim.stableLines,
        let coefficients = Self.fitQuadratic(background, keep: keep)
      else { return nil }
      let trend = Self(coefficients: coefficients, count: count, scale: 0)
      let scale = trend.robustScale(background, keep: keep)
      if pass >= 2 || !trend.clip(background, keep: &keep, scale: scale) {
        guard scale > 0 else { return nil }
        self.init(coefficients: coefficients, count: count, scale: scale)
        return
      }
      pass += 1
    }
  }

  private init(coefficients: [Double], count: Int, scale: Double) {
    self.coefficients = coefficients
    self.count = count
    self.scale = scale
  }

  /// The profile position as u ∈ [−1, 1).
  func position(_ index: Int) -> Double {
    (Double(index) - Double(count) / 2) / (Double(count) / 2)
  }

  /// The trend at line `index`.
  func value(at index: Int) -> Double {
    let along = position(index)
    return coefficients[0] + coefficients[1] * along + coefficients[2] * along * along
  }

  private func robustScale(_ background: [Double], keep: [Bool]) -> Double {
    let residuals = background.indices.filter { keep[$0] }.map {
      abs(background[$0] - value(at: $0))
    }.sorted()
    guard !residuals.isEmpty else { return 0 }
    return max(1.4826 * residuals[residuals.count / 2], 1e-6 * abs(coefficients[0]))
  }

  /// Drops lines further than 2.5 scales from the trend; reports whether any were dropped.
  private func clip(_ background: [Double], keep: inout [Bool], scale: Double) -> Bool {
    var dropped = false
    for index in background.indices
    where keep[index] && abs(background[index] - value(at: index)) > 2.5 * scale {
      keep[index] = false
      dropped = true
    }
    return dropped
  }

  /// Least squares over the kept lines, by the normal equations.
  private static func fitQuadratic(_ background: [Double], keep: [Bool]) -> [Double]? {
    let shape = Self(coefficients: [0, 0, 0], count: background.count, scale: 0)
    var matrix = [[Double]](repeating: [0, 0, 0, 0], count: 3)
    for index in background.indices where keep[index] {
      let along = shape.position(index)
      let terms = [1, along, along * along]
      for row in 0..<3 {
        for column in 0..<3 { matrix[row][column] += terms[row] * terms[column] }
        matrix[row][3] += terms[row] * background[index]
      }
    }
    return solve3(matrix)
  }

  /// Gaussian elimination with partial pivoting on a 3×4 augmented matrix.
  static func solve3(_ input: [[Double]]) -> [Double]? {
    var matrix = input
    for column in 0..<3 {
      let pivot = (column..<3).max { abs(matrix[$0][column]) < abs(matrix[$1][column]) } ?? column
      guard abs(matrix[pivot][column]) >= 1e-12 else { return nil }
      matrix.swapAt(column, pivot)
      for row in 0..<3 where row != column {
        let factor = matrix[row][column] / matrix[column][column]
        for index in column..<4 { matrix[row][index] -= factor * matrix[column][index] }
      }
    }
    let out = (0..<3).map { matrix[$0][3] / matrix[$0][$0] }
    return out.allSatisfy(\.isFinite) ? out : nil
  }
}
