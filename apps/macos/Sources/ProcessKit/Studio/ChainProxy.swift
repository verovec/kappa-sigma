/// The chain input reduced for a drag (card 0189): built once per edit from the full one, kept
/// beside it in `ChainInput`.
struct ChainProxy {
  /// The reduction factor (> 1).
  let factor: Int
  /// Step k's input, its layers and their statistics, reduced.
  let state: ChainState
  /// The recorded masks of the steps from k, reduced, by index.
  let masks: [Int: GPUImage]
}
