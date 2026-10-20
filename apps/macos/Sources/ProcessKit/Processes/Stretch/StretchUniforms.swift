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
    values[Slot.knee] = Float(ceiling - 0.05 > 0 ? ceiling - 0.05 : ceiling * 0.9)
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

  private mutating func setGHS(_ params: ParamSet) throws {}

  private mutating func setAsinh(_ params: ParamSet) {}
}
