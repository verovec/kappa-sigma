internal import RenderKit

/// The kernel's `p[]` (see Levels.metal), from the panel values only (R2).
struct LevelsUniforms {
  /// Slots of `p[]`.
  enum Slot {
    static let channels = 0
    /// 1 when the per-channel triples apply (unlinked).
    static let unlinked = 1
    /// Four triples (RGB/K, R, G, B), each: active, c0, m, c1.
    static let triples = 2
    /// Active, low, high.
    static let output = 18
    static let count = 21
  }

  private(set) var values = [Float](repeating: 0, count: Slot.count)

  /// Uniforms for `params` on `channels` planes; an identity triple or output range is marked
  /// inactive, so the untouched process returns its input bit for bit.
  init(params: ParamSet, channels: Int) throws {
    values[Slot.channels] = Float(channels)
    let unlinked = !params.flag("linked") && channels == 3
    values[Slot.unlinked] = unlinked ? 1 : 0
    for (index, triple) in LevelsProcess.triples.enumerated() {
      let stf = LevelsProcess.stf(triple, of: params)
      let used = triple == "rgb" || unlinked
      guard used, stf != .identity else { continue }
      // c1 ≤ c0 would make every value black or white: refused with the reason, never adjusted.
      guard stf.highlights > stf.shadows else {
        throw ProcessError.invalidParameter(
          "the \(triple) shadows (\(stf.shadows)) must stay below the highlights "
            + "(\(stf.highlights))")
      }
      let base = Slot.triples + 4 * index
      values[base] = 1
      values[base + 1] = Float(stf.shadows)
      values[base + 2] = Float(stf.midtone)
      values[base + 3] = Float(stf.highlights)
    }
    let (low, high) = (params.number("outputLow"), params.number("outputHigh"))
    if low != 0 || high != 1 {
      values[Slot.output] = 1
      values[Slot.output + 1] = Float(low)
      values[Slot.output + 2] = Float(high)
    }
  }
}
