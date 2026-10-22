/// The STF of up to four channels as the shaders' `float[4]` lanes.
///
/// A missing channel repeats the last one, no STF is zeros with `enabled` 0. Shared by
/// `DisplayUniforms` and `HistogramUniforms`, so both kernels read the same numbers.
struct STFLanes {
  /// c0 per lane.
  var shadows: SIMD4<Float>
  /// m per lane.
  var midtone: SIMD4<Float>
  /// c1 per lane.
  var highlights: SIMD4<Float>
  /// 1 when an STF applies.
  var enabled: UInt32

  /// The lanes of `stf` (`nil` or empty: off).
  init(_ stf: [STFParameters]?) {
    func lane(_ value: (STFParameters) -> Double) -> SIMD4<Float> {
      let values = (0..<4).map { index -> Float in
        guard let stf, !stf.isEmpty else { return 0 }
        return Float(value(stf[min(index, stf.count - 1)]))
      }
      return SIMD4(values)
    }
    shadows = lane(\.shadows)
    midtone = lane(\.midtone)
    highlights = lane(\.highlights)
    enabled = stf?.isEmpty == false ? 1 : 0
  }
}
