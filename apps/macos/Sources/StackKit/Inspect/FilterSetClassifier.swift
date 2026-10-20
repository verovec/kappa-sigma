/// A set's per-channel sky level, in ADU above the bias floor.
package struct ChannelSky: Equatable, Sendable {
  package var r: Double
  package var g: Double
  package var b: Double

  /// The three channels.
  package init(r: Double, g: Double, b: Double) {
    self.r = r
    self.g = g
    self.b = b
  }

  /// The scalar the rate thresholds are written against: the mean of the channels.
  package var amplitude: Double { (r + g + b) / 3 }

  /// The dual-band signature: Ha feeds red hardest and only OIII feeds blue, so R > G > B.
  package var isRedDominant: Bool { r > g && g > b }

  /// The broadband signature, the exact complement: red does not lead.
  package var isGreenBlueDominant: Bool { g >= r || b >= r }

  func scaled(_ factor: Double) -> Self { Self(r: r * factor, g: g * factor, b: b * factor) }
}

/// Was a one-shot-colour night shot through a dual-band clip (`internal/inspect/filterset.go`)?
///
/// Two signals — the sky rate in electrons and the colour — must BOTH agree, else `unknown`: a
/// wrong verdict mis-stacks a night, an honest unknown costs nothing.
package enum FilterSetClassifier {
  /// Sky above the pedestal per 120 s, electrons: dual-band measured 2.3–6.7, broadband 34.9–43.4.
  static let dualbandMaxPer120e = 10.0
  static let broadbandMinPer120e = 20.0
  static let normalizeExposureMs = 120_000.0
  /// Symmetric trim of the sky sample: the stars live in the bright tail, the pedestal noise is
  /// symmetric.
  static let trimLow = 0.10
  static let trimHigh = 0.90
  static let trimMinSamples = 64
  static let sampleCap = 250_000
  /// Frames sampled per set: the sky is a property of the night.
  static let sampleFrames = 3

  /// The verdict for a sky (ADU above the floor) at an exposure and an EGAIN (e⁻/ADU).
  ///
  /// No EGAIN or no exposure is no verdict: an ADU threshold measures the gain as much as the sky.
  package static func classify(_ sky: ChannelSky, exposureMs: Int, eGain: Double) -> FilterSet {
    guard exposureMs > 0, eGain > 0, eGain.isFinite else { return .unknown }
    let rate = sky.scaled(normalizeExposureMs / Double(exposureMs))
    let electrons = rate.amplitude * eGain
    guard electrons > 0, electrons.isFinite else { return .unknown }
    if electrons <= dualbandMaxPer120e && rate.isRedDominant { return .dualband }
    if electrons >= broadbandMinPer120e && rate.isGreenBlueDominant { return .broadband }
    return .unknown
  }

  /// (x, y) of R, G1, G2, B inside the 2×2 cell of each Bayer pattern.
  private static let offsets: [String: [(Int, Int)]] = [
    "RGGB": [(0, 0), (1, 0), (0, 1), (1, 1)], "BGGR": [(1, 1), (1, 0), (0, 1), (0, 0)],
    "GRBG": [(1, 0), (0, 0), (1, 1), (0, 1)], "GBRG": [(0, 1), (0, 0), (1, 1), (1, 0)],
  ]

  /// The per-channel sky of an undebayered mosaic, each primary read at its own cell position;
  /// `nil` for an unknown pattern or a frame too small.
  package static func cfaSky(_ pixels: [Float], width: Int, height: Int, pattern: String)
    -> ChannelSky?
  {
    let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let cell = offsets[key], width >= 2, height >= 2, pixels.count >= width * height else {
      return nil
    }
    let cells = (width / 2) * (height / 2)
    let stride =
      cells <= sampleCap ? 1 : Int((Double(cells) / Double(sampleCap)).squareRoot().rounded(.up))
    var red: [Double] = []
    var green: [Double] = []
    var blue: [Double] = []
    for y in Swift.stride(from: 0, to: height - 1, by: 2 * stride) {
      for x in Swift.stride(from: 0, to: width - 1, by: 2 * stride) {
        let at = { (offset: (Int, Int)) in Double(pixels[(y + offset.1) * width + x + offset.0]) }
        red.append(at(cell[0]))
        green += [at(cell[1]), at(cell[2])]
        blue.append(at(cell[3]))
      }
    }
    guard !red.isEmpty else { return nil }
    return ChannelSky(r: trimmedMean(red), g: trimmedMean(green), b: trimmedMean(blue))
  }

  /// The per-channel sky of an already-debayered frame (three planes).
  static func planeSky(_ planes: [[Float]]) -> ChannelSky? {
    guard planes.count >= 3, planes.prefix(3).allSatisfy({ !$0.isEmpty }) else { return nil }
    let level = { (plane: [Float]) -> Double in
      let step = plane.count > sampleCap ? plane.count / sampleCap : 1
      return trimmedMean(Swift.stride(from: 0, to: plane.count, by: step).map { Double(plane[$0]) })
    }
    return ChannelSky(r: level(planes[0]), g: level(planes[1]), b: level(planes[2]))
  }

  /// Mean between the 10th and 90th percentile; a plain mean under 64 samples.
  static func trimmedMean(_ input: [Double]) -> Double {
    guard !input.isEmpty else { return 0 }
    var values = input
    var low = 0
    var high = values.count
    if values.count >= trimMinSamples {
      values.sort()
      low = Int(Double(values.count) * trimLow)
      high = Int(Double(values.count) * trimHigh)
      if low >= high { (low, high) = (0, values.count) }
    }
    return values[low..<high].reduce(0, +) / Double(high - low)
  }
}
