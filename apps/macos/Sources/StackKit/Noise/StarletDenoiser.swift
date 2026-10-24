internal import ImageKit

/// The scale-adaptive, SNR-protected starlet denoiser (`noise.DenoiseWeighted`), weighted per
/// pixel.
///
/// The threshold at a pixel is K[j] · σ_white(j) · σ_local · weight. A pixel of weight 0 stays
/// byte-identical; a colour image is denoised in luminance only, its chroma kept exactly.
package enum StarletDenoiser {
  /// The deep-sky preset (`DefaultOptions`).
  static let thresholds = [3.0, 2.5, 1.8, 1.0, 0.0]

  /// Denoises `planes` in place with `weights` (one per pixel).
  package static func denoise(_ planes: inout [[Float]], width: Int, height: Int, weights: [Float])
  {
    guard width > 0, height > 0, weights.count == width * height else { return }
    if planes.count == 3 {
      let old = (0..<weights.count).map { (planes[0][$0] + planes[1][$0] + planes[2][$0]) / 3 }
      var luminance = old
      denoisePlane(&luminance, width: width, height: height, weights: weights)
      for channel in 0..<3 {
        for index in old.indices where luminance[index] != old[index] {
          planes[channel][index] = luminance[index] + (planes[channel][index] - old[index])
        }
      }
      return
    }
    for channel in planes.indices {
      denoisePlane(&planes[channel], width: width, height: height, weights: weights)
    }
  }

  /// One plane.
  ///
  /// Decompose, build the noise and protection maps, threshold, reconstruct, copy back where the
  /// weight is positive. Soft-fails (plane untouched) on non-finite data.
  static func denoisePlane(_ plane: inout [Float], width: Int, height: Int, weights: [Float]) {
    guard plane.allSatisfy(\.isFinite) else { return }
    var (smooth, details) = Starlet.decompose(
      plane, width: width, height: height, scales: thresholds.count)
    guard let maps = maps(smooth: smooth, details: details, width: width, height: height) else {
      return
    }
    for (scale, k) in thresholds.enumerated() where k > 0 {
      let base = k * Starlet.scaleSigma(scale)
      details[scale] = shrink(
        details[scale], threshold: { base * Double(maps.sigma[$0]) * Double(weights[$0]) },
        protect: { Double(maps.mask[$0]) })
    }
    smooth = Starlet.reconstruct(smooth, details)
    guard smooth.allSatisfy(\.isFinite) else { return }
    for index in plane.indices where weights[index] > 0 { plane[index] = smooth[index] }
  }

  /// The share of a pixel `snr` σ above the background that is kept as it is (0 below the
  /// `StarletNoise.protection` band, 1 above it, a smoothstep between).
  package static func protection(snr: Double) -> Double {
    NoiseStats.smoothstep(StarletNoise.protection.low, StarletNoise.protection.high, snr)
  }

  /// One detail plane soft-thresholded by `threshold(index)`, a `protect(index)` share of each
  /// value (0…1) kept as it is: the per-scale step, shared with the Studio's denoise oracle.
  package static func shrink(
    _ detail: [Float], threshold: (Int) -> Double, protect: (Int) -> Double
  ) -> [Float] {
    detail.indices.map { index in
      let value = Double(detail[index])
      let shrunk = NoiseStats.softThreshold(value, threshold(index))
      let kept = protect(index)
      return Float((kept * value).addingProduct(1 - kept, shrunk))
    }
  }

  /// The local noise sigma and the SNR protection mask (`buildMaps`); nil when the noise floor
  /// cannot be estimated.
  static func maps(smooth: [Float], details: [[Float]], width: Int, height: Int) -> (
    sigma: [Float], mask: [Float]
  )? {
    let tiles = NoiseStats.tileSigmas(details[0], width: width, height: height)
    guard tiles.sigma > 0, tiles.sigma.isFinite else { return nil }
    let background = (0..<tiles.gridHeight).flatMap { tileY in
      (0..<tiles.gridWidth).map { tileX in
        PhotomStats.median(
          NoiseStats.tile(smooth, width: width, height: height, x: tileX, y: tileY))
      }
    }
    var scaleTwo = smooth
    for scale in 2..<max(2, details.count) {
      for index in scaleTwo.indices { scaleTwo[index] += details[scale][index] }
    }
    var sigma = [Float](repeating: 0, count: width * height)
    var mask = [Float](repeating: 0, count: width * height)
    for row in 0..<height {
      let gy = NoiseStats.gridCoordinate(row)
      for column in 0..<width {
        let index = row * width + column
        let gx = NoiseStats.gridCoordinate(column)
        sigma[index] = Float(
          NoiseStats.bilinear(
            tiles.grid, width: tiles.gridWidth, height: tiles.gridHeight, x: gx, y: gy))
        let local = Double(sigma[index])
        guard local > 0 else {
          mask[index] = 1
          continue
        }
        let level = NoiseStats.bilinear(
          background, width: tiles.gridWidth, height: tiles.gridHeight, x: gx, y: gy)
        mask[index] = Float(protection(snr: (Double(scaleTwo[index]) - level) / local))
      }
    }
    return (sigma, mask)
  }

  /// The global noise of plane 0: the median tile sigma of a 4-scale first detail plane
  /// (`noise.Measure(...).Sigma`).
  package static func measure(_ plane: [Float], width: Int, height: Int) -> Double {
    guard width > 0, height > 0, !plane.isEmpty else { return 0 }
    // The first detail plane (c₀ − c₁) is the same whatever the depth: one scale is enough.
    let (_, details) = Starlet.decompose(plane, width: width, height: height, scales: 1)
    return NoiseStats.tileSigmas(details[0], width: width, height: height).sigma
  }
}
