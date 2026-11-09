package import ImageKit
internal import RenderKit

extension LayerStats {
  /// The statistics of `image`, measured the way RenderKit's autostretch does (upper median and
  /// MADN of the finite values, a stride above 64 Ki samples; minimum and maximum).
  ///
  /// A pipeline step after the first gets the statistics of the image it receives, as the Studio
  /// would show for that image — never a process measuring itself (R2).
  package static func measured(_ image: AstroImage) -> LayerStats {
    LayerStats(
      channels: image.planes.map { plane in
        let (median, madn) = AutoSTF.medianAndMADN(plane)
        let (minimum, maximum) = finiteExtremes(plane)
        return ChannelStats(median: median, madn: madn, minimum: minimum, maximum: maximum)
      })
  }

  /// The smallest and largest finite value of `plane` (`0` for each when it has none), the first
  /// of equal values winning (signed zeros), in one pass.
  ///
  /// Written out on the buffer on purpose (card 0187): the lazy `filter(\.isFinite).min()` it
  /// replaces ran a key-path getter and generic metadata lookups per pixel — ~19 s a 26 Mpx plane
  /// unoptimised, the Studio's every preview and open — and vDSP's extremes say nothing about a
  /// NaN, which a stacked plane can hold. The pointer, not `Span`: 0.8 s against 5.3 s for
  /// 3 × 26 Mpx unoptimised (`LiveLayerStatsBudgetTests`), the build the app runs in daily.
  static func finiteExtremes(_ plane: [Float]) -> (minimum: Double, maximum: Double) {
    plane.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else { return (0, 0) }
      var minimum = Float.nan
      var maximum = Float.nan
      var index = 0
      while index < buffer.count {
        let value = unsafe base[index]
        index += 1
        guard value.isFinite else { continue }
        // A NaN compares false: the first finite value takes both.
        if !(minimum <= value) { minimum = value }
        if !(maximum >= value) { maximum = value }
      }
      guard minimum.isFinite else { return (0, 0) }
      return (Double(minimum), Double(maximum))
    }
  }

  /// These statistics with the continuum fit (`continuum_k`, its reference) of `recorded`: a
  /// layer measured again after a step keeps the fit made on the stack (card 0090).
  package func keepingFit(of recorded: LayerStats?) -> LayerStats {
    guard let recorded, recorded.continuumK != nil || recorded.continuumReference != nil else {
      return self
    }
    return LayerStats(
      channels: channels, continuumK: recorded.continuumK,
      continuumReference: recorded.continuumReference)
  }
}
