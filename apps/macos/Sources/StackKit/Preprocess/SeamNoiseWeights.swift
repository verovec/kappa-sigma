internal import Foundation

/// The per-pixel strength of the seam noise pass (`seamNoiseWeights`): the excess noise factor
/// √(depth_max / depth) − 1 of the coverage, smoothed by normalised convolution over the covered
/// cells (σ = 12 cells), clamped to [0, 2.5], bilinearly upsampled; never-covered pixels stay 0.
package enum SeamNoiseWeights {
  static let maxWeight: Float = 2.5
  static let blurCells = 12.0
  /// Below this depth ratio the noise step is invisible.
  static let minDepthRatio = 1.3

  /// The weights of a `width` × `height` master, or why the pass is skipped.
  package static func weights(_ grid: CoverageGrid, width: Int, height: Int) -> (weights: [Float]?, reason: String) {
    guard !grid.counts.isEmpty else { return (nil, "no coverage grid") }
    guard grid.width == (width + grid.scale - 1) / grid.scale, grid.height == (height + grid.scale - 1) / grid.scale
    else { return (nil, "coverage grid does not match the master canvas") }
    let covered = grid.counts.filter { $0 > 0 }
    guard let deepest = covered.max(), let shallowest = covered.min() else { return (nil, "no covered cells") }
    guard Double(deepest) / Double(shallowest) >= minDepthRatio else {
      return (nil, "stack depth nearly uniform (\(shallowest)→\(deepest)) — no visible noise step")
    }
    let values = grid.counts.map { Float($0) }
    let coverage = grid.counts.map { $0 > 0 ? Float(1) : 0 }
    let blurredValues = gaussianBlur(values, width: grid.width, height: grid.height, sigma: blurCells)
    let blurredCoverage = gaussianBlur(coverage, width: grid.width, height: grid.height, sigma: blurCells)
    let cells = grid.counts.indices.map { index -> Float in
      guard grid.counts[index] > 0, blurredCoverage[index] > 1e-6 else { return 0 }
      let smooth = max(1, Double(blurredValues[index] / blurredCoverage[index]))
      let weight = (Double(deepest) / smooth).squareRoot() - 1
      return Float(min(max(weight, 0), Double(maxWeight)))
    }
    return (upsample(cells, grid: grid, width: width, height: height), "")
  }

  /// Bilinear upsampling with pixel-centre mapping; a pixel whose own cell is uncovered stays 0.
  static func upsample(_ cells: [Float], grid: CoverageGrid, width: Int, height: Int) -> [Float] {
    var out = [Float](repeating: 0, count: width * height)
    let scale = Double(grid.scale)
    for row in 0..<height {
      let gy = (Double(row) + 0.5) / scale - 0.5
      for column in 0..<width {
        let cell = min(row / grid.scale, grid.height - 1) * grid.width + min(column / grid.scale, grid.width - 1)
        guard grid.counts[cell] > 0 else { continue }
        out[row * width + column] = bilinear(
          cells, width: grid.width, height: grid.height, x: (Double(column) + 0.5) / scale - 0.5, y: gy)
      }
    }
    return out
  }

  /// A cell grid sampled at fractional coordinates, edges clamped (`bilinearCell`; the second
  /// product of each pair fused, as arm64 Go compiles `a*b + c*d`).
  static func bilinear(_ grid: [Float], width: Int, height: Int, x: Double, y: Double) -> Float {
    let (x0, y0) = (Int(x.rounded(.down)), Int(y.rounded(.down)))
    let (fx, fy) = (x - Double(x0), y - Double(y0))
    let cell = { (cx: Int, cy: Int) in
      Double(grid[min(max(cy, 0), height - 1) * width + min(max(cx, 0), width - 1)])
    }
    let top = (cell(x0, y0) * (1 - fx)).addingProduct(cell(x0 + 1, y0), fx)
    let bottom = (cell(x0, y0 + 1) * (1 - fx)).addingProduct(cell(x0 + 1, y0 + 1), fx)
    return Float((top * (1 - fy)).addingProduct(bottom, fy))
  }

  /// Three box blurs approximating a Gaussian (`imgops.GaussianBlur`, Kovesi's construction).
  static func gaussianBlur(_ source: [Float], width: Int, height: Int, sigma: Double) -> [Float] {
    var out = source
    guard sigma > 0 else { return out }
    var scratch = [Float](repeating: 0, count: source.count)
    for box in boxes(sigma: sigma, count: 3) {
      let radius = (box - 1) / 2
      guard radius >= 1 else { continue }
      boxBlur(out, into: &scratch, count: height, length: width, radius: radius) { $0 * width + $1 }
      boxBlur(scratch, into: &out, count: width, length: height, radius: radius) { $1 * width + $0 }
    }
    return out
  }

  /// `count` odd box widths whose succession approximates a Gaussian of `sigma`.
  static func boxes(sigma: Double, count: Int) -> [Int] {
    let ideal = (12 * sigma * sigma / Double(count) + 1).squareRoot()
    var lower = Int(ideal.rounded(.down))
    if lower % 2 == 0 { lower -= 1 }
    let upper = lower + 2
    let numerator = 12 * sigma * sigma - Double(count * lower * lower) - Double(4 * count * lower) - Double(3 * count)
    let small = Int((numerator / Double(-4 * lower - 4)).rounded(.toNearestOrAwayFromZero))
    return (0..<count).map { $0 < small ? lower : upper }
  }

  /// A running-sum moving average of `radius` along each of `count` lines of `length`, edges
  /// clamped; `index(line, position)` addresses the plane.
  static func boxBlur(
    _ source: [Float], into destination: inout [Float], count: Int, length: Int, radius: Int,
    index: (Int, Int) -> Int
  ) {
    let inverse = 1.0 / Double(2 * radius + 1)
    let clamp = { (position: Int) in min(max(position, 0), length - 1) }
    for line in 0..<count {
      var sum = 0.0
      for offset in -radius...radius { sum += Double(source[index(line, clamp(offset))]) }
      for position in 0..<length {
        destination[index(line, position)] = Float(sum * inverse)
        sum += Double(source[index(line, clamp(position + radius + 1))]) - Double(source[index(line, clamp(position - radius))])
      }
    }
  }
}
