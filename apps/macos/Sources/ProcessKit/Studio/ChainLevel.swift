/// At which resolution a chain preview renders (card 0189).
package enum ChainLevel: Sendable {
  /// Every step at full resolution: the pixels the revise writes.
  case full
  /// Every step on the input reduced by `ProxyLevel.factor` (every `.px` value scaled with it),
  /// the result brought back to the full size: what a drag shows between two full renders.
  /// A chain whose input already fits renders full.
  case proxy
}
