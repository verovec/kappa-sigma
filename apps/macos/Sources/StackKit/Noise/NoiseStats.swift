internal import ImageKit

/// The robust statistics of the noise tools (`noise/stats.go`, `sigma.go`).
///
/// 64-px tiles, MAD sigmas, bilinear grid sampling; the medians and percentiles are the ones in
/// `PhotomStats`, the single copy of the legacy interpolation.
enum NoiseStats {
  static let tileSize = 64

  /// 1.4826 · MAD.
  static func robustSigma(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let center = PhotomStats.median(values)
    return 1.4826 * PhotomStats.median(values.map { abs($0 - center) })
  }

  /// The tile (tx, ty) of a plane, clipped to its bounds.
  static func tile(_ plane: [Float], width: Int, height: Int, x tileX: Int, y tileY: Int)
    -> [Double]
  {
    let (x0, y0) = (tileX * tileSize, tileY * tileSize)
    let (x1, y1) = (min(x0 + tileSize, width), min(y0 + tileSize, height))
    var out: [Double] = []
    out.reserveCapacity((x1 - x0) * (y1 - y0))
    for row in y0..<y1 {
      for column in x0..<x1 { out.append(Double(plane[row * width + column])) }
    }
    return out
  }

  /// Per-tile sigma of the first detail plane over its white-noise sigma, clamped to
  /// [0.25, 4]·σ_G; σ_G (median tile) and the 90th percentile (`tileSigmaGrid`).
  static func tileSigmas(_ detail: [Float], width: Int, height: Int) -> TileSigmaGrid {
    let (gridWidth, gridHeight) = (
      (width + tileSize - 1) / tileSize, (height + tileSize - 1) / tileSize
    )
    var grid: [Double] = []
    for tileY in 0..<gridHeight {
      for tileX in 0..<gridWidth {
        grid.append(
          robustSigma(tile(detail, width: width, height: height, x: tileX, y: tileY))
            / StarletNoise.whiteNoiseSigma[0])
      }
    }
    let sorted = grid.sorted()
    let sigma = PhotomStats.percentile(sorted: sorted, 50)
    let p90 = PhotomStats.percentile(sorted: sorted, 90)
    return TileSigmaGrid(
      grid: grid.map { min(max($0, 0.25 * sigma), 4 * sigma) }, gridWidth: gridWidth,
      gridHeight: gridHeight, sigma: sigma, p90: p90)
  }

  /// A pixel index as a fractional tile coordinate (tile centres at integers).
  static func gridCoordinate(_ index: Int) -> Double {
    (Double(index) + 0.5) / Double(tileSize) - 0.5
  }

  /// A grid sampled bilinearly at (gx, gy), clamped to its edges (`bilinearSample`).
  static func bilinear(_ grid: [Double], width: Int, height: Int, x gx: Double, y gy: Double)
    -> Double
  {
    let (x, y) = (min(max(gx, 0), Double(width - 1)), min(max(gy, 0), Double(height - 1)))
    let (x0, y0) = (Int(x.rounded(.down)), Int(y.rounded(.down)))
    let (x1, y1) = (min(x0 + 1, width - 1), min(y0 + 1, height - 1))
    let (fx, fy) = (x - Double(x0), y - Double(y0))
    let (v00, v10) = (grid[y0 * width + x0], grid[y0 * width + x1])
    let (v01, v11) = (grid[y1 * width + x0], grid[y1 * width + x1])
    let top = v00.addingProduct(fx, v10 - v00)
    let bottom = v01.addingProduct(fx, v11 - v01)
    return top.addingProduct(fy, bottom - top)
  }

  /// The Hermite S-curve: 0 for x ≤ lower, 1 for x ≥ upper.
  static func smoothstep(_ lower: Double, _ upper: Double, _ x: Double) -> Double {
    guard lower < upper else { return x < lower ? 0 : 1 }
    let ramp = min(max((x - lower) / (upper - lower), 0), 1)
    return ramp * ramp * (3 - 2 * ramp)
  }

  /// sign(v) · max(|v| − t, 0).
  static func softThreshold(_ value: Double, _ threshold: Double) -> Double {
    let magnitude = abs(value) - threshold
    return magnitude <= 0 ? 0 : (value < 0 ? -magnitude : magnitude)
  }
}
