internal import Foundation

extension TrailSegmentDetector {
  /// The seeds within ⊥2 of the peak line, in 4-connected components of two cells or more, when
  /// they form a long, thin, centred streak (`confirmInliers`); nil for a star cluster grazing it.
  static func confirmInliers(_ seeds: [Int], grid: Grid, line: HoughLine) -> [Int]? {
    var near = [Bool](repeating: false, count: grid.cells.count)
    for seed in seeds {
      let (x, y) = (Double(seed % grid.width), Double(seed / grid.width))
      if abs(x * line.cosine + y * line.sine - line.rho) <= 2 { near[seed] = true }
    }
    let labels = componentLabels(near, width: grid.width, height: grid.height)
    var sizes: [Int: Int] = [:]
    for label in labels where label > 0 { sizes[label, default: 0] += 1 }
    let inliers = labels.indices.filter { labels[$0] > 0 && (sizes[labels[$0]] ?? 0) >= 2 }
    guard inliers.count >= 16, elongated(inliers, grid: grid, line: line) else { return nil }
    return inliers
  }

  /// Extent ≥ 25% of the short side, extent / (2·RMS⊥) ≥ 8, mean |⊥| ≤ 3 (`elongated`).
  static func elongated(_ inliers: [Int], grid: Grid, line: HoughLine) -> Bool {
    let (dx, dy) = (-line.sine, line.cosine)
    var (low, high, squares, absolute) = (Double.infinity, -Double.infinity, 0.0, 0.0)
    for cell in inliers {
      let (x, y) = (Double(cell % grid.width), Double(cell / grid.width))
      let t = x * dx + y * dy
      (low, high) = (min(low, t), max(high, t))
      let distance = x * line.cosine + y * line.sine - line.rho
      squares += distance * distance
      absolute += abs(distance)
    }
    let count = Double(inliers.count)
    let (length, rms) = (high - low, (squares / count).squareRoot())
    if length < 0.25 * Double(min(grid.width, grid.height)) { return false }
    if rms > 0 && length / (2 * rms) < 8 { return false }
    return absolute / count <= 3
  }

  /// 4-connected component ids (> 0) of the true cells, 0 elsewhere (`imgops.Label`); only the
  /// partition matters here, not the numbering.
  static func componentLabels(_ mask: [Bool], width: Int, height: Int) -> [Int] {
    var labels = [Int](repeating: 0, count: mask.count)
    var next = 0
    var stack: [Int] = []
    for start in mask.indices where mask[start] && labels[start] == 0 {
      next += 1
      labels[start] = next
      stack.append(start)
      while let cell = stack.popLast() {
        let (x, y) = (cell % width, cell / width)
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
        where nx >= 0 && nx < width && ny >= 0 && ny < height {
          let neighbour = ny * width + nx
          if mask[neighbour] && labels[neighbour] == 0 {
            labels[neighbour] = next
            stack.append(neighbour)
          }
        }
      }
    }
    return labels
  }
}
