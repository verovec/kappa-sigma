/// CPU reference of the sky desaturation: `chromasmooth.go` with only the `sky_desat` passes on
/// (`FinePx = BgPx = 0`), in Double, with `imgops.GaussianBlur` (three Kovesi boxes, edges
/// clamped) — the sky level and chroma σ given, as the process takes them from the bundle.
enum SkyDesatOracle {
  struct Options {
    var strength = 1.0
    var keepCool = false
    var scalePx = 48.0
    var starSigmaPx = 2.0
    var coreGuardPx = 4
    var coreLevel = 0.85
    var star = (low: 0.005, high: 0.02)
    var nebula = (low: 0.02, high: 0.10)
    var floor = (low: 1e-4, high: 4e-4)
  }

  static func smoothstep(_ low: Double, _ high: Double, _ x: Double) -> Double {
    if x <= low { return 0 }
    if x >= high { return 1 }
    let along = (x - low) / (high - low)
    return along * along * (3 - 2 * along)
  }

  /// `boxesForGauss(sigma, 3)`.
  static func boxes(sigma: Double) -> [Int] {
    let ideal = (12 * sigma * sigma / 3 + 1).squareRoot()
    var lower = Int(ideal.rounded(.down))
    if lower % 2 == 0 { lower -= 1 }
    let small =
      ((12 * sigma * sigma - Double(3 * lower * lower) - Double(12 * lower) - 9)
      / Double(-4 * lower - 4)).rounded()
    return (0..<3).map { Double($0) < small ? lower : lower + 2 }
  }

  static func gaussian(_ plane: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
    guard sigma > 0 else { return plane }
    var out = plane
    for box in boxes(sigma: sigma) {
      let radius = (box - 1) / 2
      guard radius >= 1 else { continue }
      out = boxPass(out, width: width, height: height, radius: radius, horizontal: true)
      out = boxPass(out, width: width, height: height, radius: radius, horizontal: false)
    }
    return out
  }

  static func boxPass(
    _ plane: [Double], width: Int, height: Int, radius: Int, horizontal: Bool
  ) -> [Double] {
    var out = plane
    for y in 0..<height {
      for x in 0..<width {
        var sum = 0.0
        for k in -radius...radius {
          let (sx, sy) =
            horizontal ? (min(max(x + k, 0), width - 1), y) : (x, min(max(y + k, 0), height - 1))
          sum += plane[sy * width + sx]
        }
        out[y * width + x] = sum / Double(2 * radius + 1)
      }
    }
    return out
  }

  /// The sky-desaturated RGB planes.
  static func apply(
    _ planes: [[Float]], width: Int, height: Int, sky: Double, sigmaC: Double, _ opts: Options
  ) -> [[Float]] {
    let rgb = planes.map { $0.map(Double.init) }
    let count = width * height
    let mean = (0..<count).map { (rgb[0][$0] + rgb[1][$0] + rgb[2][$0]) / 3 }
    let lumS = gaussian(mean, width: width, height: height, sigma: opts.starSigmaPx)
    let coarse = opts.scalePx / 3.0.squareRoot()
    let lumC = gaussian(mean, width: width, height: height, sigma: coarse)
    let starW = (0..<count).map {
      smoothstep(opts.star.low, opts.star.high, (lumS[$0] - lumC[$0]) / sky)
    }
    let smD = rgb.map { plane in
      gaussian(
        (0..<count).map { (plane[$0] - mean[$0]) * (1 - starW[$0]) }, width: width, height: height,
        sigma: coarse)
    }
    let core = coreMask(mean, width: width, height: height, opts)
    var out = planes
    for index in 0..<count where !core[index] {
      let star = starW[index]
      let rel = (lumC[index] - sky) / sky
      var w1 = opts.strength * (1 - star) * (1 - smoothstep(opts.nebula.low, opts.nebula.high, rel))
      if opts.keepCool {
        let dev = (rgb[0][index] - rgb[2][index]) - (smD[0][index] - smD[2][index])
        w1 *= smoothstep(-sigmaC, sigmaC, dev)
      }
      let floor =
        1 - opts.strength * (1 - star) * (1 - smoothstep(opts.floor.low, opts.floor.high, rel))
      for plane in 0..<3 {
        var chroma = rgb[plane][index] - mean[index]
        chroma += w1 * (smD[plane][index] - chroma)
        chroma *= floor
        out[plane][index] = Float(mean[index] + chroma)
      }
    }
    return out
  }

  /// Pixels within `coreGuardPx` (4-neighbour steps) of a mean above `coreLevel`.
  static func coreMask(_ mean: [Double], width: Int, height: Int, _ opts: Options) -> [Bool] {
    let r = opts.coreGuardPx
    return (0..<width * height).map { index in
      let (x, y) = (index % width, index / width)
      for dy in -r...r {
        for dx in -r...r where abs(dx) + abs(dy) <= r {
          let (sx, sy) = (x + dx, y + dy)
          guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
          if mean[sy * width + sx] > opts.coreLevel { return true }
        }
      }
      return false
    }
  }
}
