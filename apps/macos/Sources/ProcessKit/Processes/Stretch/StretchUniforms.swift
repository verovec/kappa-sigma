internal import Foundation
internal import RenderKit

/// The kernel's `p[]` (see Stretch.metal), derived from the parameters and the bundle stats.
///
/// Everything the shader applies is computed here, in double, from values the panel shows and
/// the bundle's statistics: the shader never measures the image (R2).
struct StretchUniforms {
  /// Slots of `p[]`.
  enum Slot {
    static let mode = 0
    static let channels = 1
    static let ceiling = 2
    static let knee = 3
    /// Three per channel: c0, 1 / (1 − c0), m.
    static let mtf = 4
    /// b, D, LP, SP, HP, f(0), 1 / (f(1) − f(0)), T(SP − LP), T′(SP − LP), T(HP − SP), T′(HP − SP).
    static let ghs = 13
    /// β, black point, 1 / asinh(β).
    static let asinh = 24
    static let count = 27
  }

  private(set) var values = [Float](repeating: 0, count: Slot.count)

  /// Uniforms for `params` on `channels` planes with `stats`.
  init(params: ParamSet, channels: Int, stats: LayerStats) throws {
    values[Slot.channels] = Float(channels)
    let ceiling = params.number("headroom")
    values[Slot.ceiling] = Float(ceiling)
    // The legacy knee: 0.05 under the ceiling (the schema keeps the ceiling ≥ 0.5).
    values[Slot.knee] = Float(ceiling - 0.05)
    switch params.choice("mode") {
    case "ghs":
      values[Slot.mode] = 1
      try setGHS(params)
    case "asinh":
      values[Slot.mode] = 2
      setAsinh(params)
    default:
      try setMTF(params, channels: channels, stats: stats)
    }
  }

  /// Siril's autostretch: c0 = median + clip · MADN in [0, 1], m = MTF(target, median − c0);
  /// linked uses the mean median and MADN of the channels.
  private mutating func setMTF(_ params: ParamSet, channels: Int, stats: LayerStats) throws {
    guard stats.channels.count >= channels else {
      throw ProcessError.invalidParameter("the stretch needs the bundle statistics of each plane")
    }
    let used = Array(stats.channels.prefix(channels))
    let (clip, target) = (params.number("shadowsClip"), params.number("targetBackground"))
    let pairs: [(median: Double, madn: Double)] =
      params.flag("linked")
      ? Array(
        repeating: (
          used.map(\.median).reduce(0, +) / Double(channels),
          used.map(\.madn).reduce(0, +) / Double(channels)
        ), count: channels)
      : used.map { ($0.median, $0.madn) }
    for (channel, pair) in pairs.enumerated() {
      let shadows = Self.shadows(median: pair.median, madn: pair.madn, clip: clip)
      // At the median (clip 0, or a plane with no noise) the midtone is 0 and the curve is a
      // hard black/white threshold: refused with the reason, never rendered or adjusted (R2).
      guard pair.median - shadows > 0 else {
        throw ProcessError.invalidParameter(
          "the shadows clip reaches the background median (MADN \(pair.madn)): lower it")
      }
      let base = Slot.mtf + 3 * channel
      values[base] = Float(shadows)
      values[base + 1] = Float(1 / (1 - shadows))
      values[base + 2] = Float(MTF.apply(target, pair.median - shadows))
    }
  }

  /// c0 = median + clip · MADN, in [0, 1).
  static func shadows(median: Double, madn: Double, clip: Double) -> Double {
    min(max(median + clip * madn, 0), 0.999_999)
  }

  /// The GHS coefficients.
  ///
  /// D = e^stretch − 1, the base transform's value and slope at the protection points, and the
  /// normalisation f(0) → 0, f(1) → 1. D = 0 is the identity.
  private mutating func setGHS(_ params: ParamSet) throws {
    let (b, strength) = (params.number("ghsIntensity"), exp(params.number("ghsStretch")) - 1)
    let (lp, sp, hp) = (
      params.number("ghsShadows"), params.number("ghsSymmetry"), params.number("ghsHighlights")
    )
    guard lp <= sp, sp <= hp else {
      throw ProcessError.invalidParameter(
        "GHS needs shadow protection ≤ symmetry point ≤ highlight protection")
    }
    let low = GHS.base(sp - lp, b: b, strength: strength)
    let high = GHS.base(hp - sp, b: b, strength: strength)
    let raw = { (x: Double) in GHS.raw(x, b: b, strength: strength, lp: lp, sp: sp, hp: hp) }
    let range = strength > 0 ? raw(1) - raw(0) : 0
    let coefficients = [
      b, strength, lp, sp, hp, strength > 0 ? raw(0) : 0, range > 0 ? 1 / range : 0, low.value,
      low.slope,
      high.value, high.slope,
    ]
    for (offset, value) in coefficients.enumerated() { values[Slot.ghs + offset] = Float(value) }
  }

  /// β, the black point and 1 / asinh(β) (0 when β = 0: the stretch is then the black lift).
  private mutating func setAsinh(_ params: ParamSet) {
    let beta = params.number("asinhStretch")
    values[Slot.asinh] = Float(beta)
    values[Slot.asinh + 1] = Float(params.number("asinhBlack"))
    values[Slot.asinh + 2] = beta > 0 ? Float(1 / asinh(beta)) : 0
  }
}
