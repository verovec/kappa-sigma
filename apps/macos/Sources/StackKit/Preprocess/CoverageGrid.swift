/// How many stacked frames cover each 8-px cell of the anchor canvas (`coverageGrid`): what the
/// seam noise weights, the seam offset overlap and the combine crop are built on.
package struct CoverageGrid: Equatable, Sendable {
  /// Cell size in canvas pixels (±8 px precision).
  package static let cellSize = 8

  package let width: Int
  package let height: Int
  package var counts: [UInt16]
  /// The frames accumulated.
  package var frames = 0
  package let scale: Int

  /// An empty grid for a `canvasWidth` × `canvasHeight` canvas.
  package init(canvasWidth: Int, canvasHeight: Int, scale: Int = cellSize) {
    width = (canvasWidth + scale - 1) / scale
    height = (canvasHeight + scale - 1) / scale
    counts = Array(repeating: 0, count: width * height)
    self.scale = scale
  }

  /// The kept frames (`homographies`, 0-based merge index → frame-to-canvas) that are not
  /// `rejected`, rasterized for frames of `frameWidth` × `frameHeight` (`rasterizeCoverage`).
  package init(
    homographies: [Int: [Double]], rejected: (Int) -> Bool, frameWidth: Int, frameHeight: Int,
    scale: Int = cellSize
  ) {
    self.init(canvasWidth: frameWidth, canvasHeight: frameHeight, scale: scale)
    for (index, homography) in homographies where !rejected(index) {
      frames += 1
      guard let quad = Self.quad(homography, width: frameWidth, height: frameHeight) else { continue }
      accumulate(quad)
    }
  }

  /// The frame's corners on the canvas; nil for a degenerate homography.
  static func quad(_ homography: [Double], width: Int, height: Int) -> [(Double, Double)]? {
    var quad: [(Double, Double)] = []
    for (x, y) in [(0.0, 0.0), (Double(width), 0), (Double(width), Double(height)), (0, Double(height))] {
      let w = homography[6] * x + homography[7] * y + homography[8]
      guard w != 0, !w.isNaN else { return nil }
      quad.append(
        ((homography[0] * x + homography[1] * y + homography[2]) / w,
          (homography[3] * x + homography[4] * y + homography[5]) / w))
    }
    return quad
  }

  /// Bumps every cell whose centre lies inside the convex quad.
  mutating func accumulate(_ quad: [(Double, Double)]) {
    let xs = quad.map(\.0)
    let ys = quad.map(\.1)
    let (x0, y0) = (max(0, Int(xs.min() ?? 0) / scale), max(0, Int(ys.min() ?? 0) / scale))
    let (x1, y1) = (min(width - 1, Int(xs.max() ?? 0) / scale), min(height - 1, Int(ys.max() ?? 0) / scale))
    guard x0 <= x1, y0 <= y1 else { return }
    for row in y0...y1 {
      let cy = (Double(row) + 0.5) * Double(scale)
      for column in x0...x1 where Self.inside(quad, x: (Double(column) + 0.5) * Double(scale), y: cy) {
        counts[row * width + column] += 1
      }
    }
  }

  /// Whether (x, y) lies inside the convex quad, either winding (`insideQuad`).
  static func inside(_ quad: [(Double, Double)], x: Double, y: Double) -> Bool {
    var sign = 0.0
    for index in 0..<4 {
      let (a, b) = (quad[index], quad[(index + 1) % 4])
      let cross = (b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0)
      if cross == 0 { continue }
      if sign == 0 {
        sign = cross
      } else if (cross > 0) != (sign > 0) {
        return false
      }
    }
    return sign != 0
  }

  /// One night's union footprint: cells any kept frame of `span` covers (`groupFootprintMask`).
  package static func footprint(
    _ span: Range<Int>, homographies: [Int: [Double]], rejected: (Int) -> Bool, frameWidth: Int,
    frameHeight: Int
  ) -> [Bool] {
    Self(
      homographies: homographies.filter { span.contains($0.key) }, rejected: rejected,
      frameWidth: frameWidth, frameHeight: frameHeight
    ).counts.map { $0 > 0 }
  }

  /// Cells reached by at least max(1, round(fraction · frames)) frames.
  package func mask(minimumFraction fraction: Double) -> [Bool] {
    let need = UInt16(max(1, Int((fraction * Double(frames)).rounded())))
    return counts.map { $0 >= need }
  }

  /// The covered fraction of a mask.
  package static func coveredFraction(_ mask: [Bool]) -> Double {
    mask.isEmpty ? 0 : Double(mask.count { $0 }) / Double(mask.count)
  }
}
