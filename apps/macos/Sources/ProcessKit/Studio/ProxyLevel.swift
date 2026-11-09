/// The reduction a drag's chain preview renders at (card 0189): an integer factor, so every
/// `.px` parameter divides by it exactly (`RenderContext.scale`) and the proxy's pixels are cells
/// of the full image.
package enum ProxyLevel {
  /// The longer side a proxy is kept under: a 6248-px frame renders at a quarter (1562 px),
  /// a 3008-px one at a half.
  package static let maxSide = 1600

  /// The smallest factor bringing the longer side of `width` × `height` to `maxSide` or under;
  /// 1 when it already fits — then there is no proxy, the full render is the frame.
  package static func factor(width: Int, height: Int, maxSide: Int = maxSide) -> Int {
    let longer = max(width, height, 1)
    return longer <= maxSide ? 1 : (longer + maxSide - 1) / maxSide
  }
}
