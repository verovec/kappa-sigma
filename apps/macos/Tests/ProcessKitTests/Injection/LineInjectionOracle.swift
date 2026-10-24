import ProcessKit
import Testing

/// The CPU oracle of `LineInjection.metal`, in Float like the kernel: per target plane `p`,
/// `base_p + Σ gain · share_p · max(line − k · ref − black, 0)` in Hα, [OIII], [SII] order, then
/// the generic mask blend `m · processed + (1 − m) · input`.
enum LineInjectionOracle {
  /// One line's values and planes.
  struct Line {
    var plane: [Float]
    var reference: [Float]
    var gain: Double
    var shares: [Double]
    var k: Double
    var black: Double
  }

  static let prefixes = ["ha", "oiii", "sii"]

  /// The lines `params` inject, read from `planes` (`Ha`, `OIII`, `SII`, `RGB` by plane) with
  /// the reference token of each line; a missing layer or reference fails the test.
  static func lines(
    params: ParamSet, planes: [String: [[Float]]], references: [String: String]
  ) throws -> [Line] {
    try zip(prefixes, ["Ha", "OIII", "SII"]).compactMap { prefix, layer in
      let gain = params.number(prefix + "Gain")
      let shares = ["Red", "Green", "Blue"].map { params.number(prefix + $0) }
      // The process's rule: a line injects when some gain × share is not 0.
      guard shares.contains(where: { gain * $0 != 0 }) else { return nil }
      let plane = try #require(planes[layer]?[0], "a gain needs its layer")
      let k = params.number(prefix + "ContinuumK")
      var reference = plane
      if Float(k) != 0 {
        // The process refuses k > 0 without a fitted plane: so does the oracle, never the line.
        let parsed = LayerPlane(try #require(references[layer], "k > 0 needs a reference"))
        reference = try #require(planes[parsed.layer]?[parsed.plane])
      }
      return Line(
        plane: plane, reference: reference, gain: gain,
        shares: shares, k: k,
        black: params.number(prefix + "Black"))
    }
  }

  /// The injected base.
  static func inject(_ base: [[Float]], lines: [Line]) -> [[Float]] {
    base.enumerated().map { plane, values in
      values.indices.map { index in
        var out = values[index]
        for line in lines {
          let weight = Float(line.gain * line.shares[plane])
          guard weight != 0 else { continue }
          let continuum = Float(line.k) == 0 ? 0 : Float(line.k) * line.reference[index]
          let excess = line.plane[index] - continuum - Float(line.black)
          // fmax in the kernel: a NaN excess adds nothing; no excess keeps the pixel's bits.
          guard excess > 0 else { continue }
          out += weight * excess
        }
        return out
      }
    }
  }

  /// `ProcessRunner`'s mask blend.
  static func blend(input: [[Float]], processed: [[Float]], mask: [Float]) -> [[Float]] {
    zip(input, processed).map { input, processed in
      mask.indices.map { index in
        let weight = mask[index]
        guard weight != 1 else { return processed[index] }
        guard weight != 0 else { return input[index] }
        return weight * processed[index] + (1 - weight) * input[index]
      }
    }
  }
}
