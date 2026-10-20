import Foundation

/// Standard normal deviates from a SplitMix64 stream (Box–Muller): deterministic per seed.
struct SeededGaussian {
  private var state: UInt64
  private var spare: Double?

  init(seed: UInt64) { state = seed }

  mutating func next() -> Double {
    if let spare {
      self.spare = nil
      return spare
    }
    let (first, second) = (max(uniform(), 1e-300), uniform())
    let radius = (-2 * log(first)).squareRoot()
    spare = radius * sin(2 * .pi * second)
    return radius * cos(2 * .pi * second)
  }

  private mutating func uniform() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
  }
}
