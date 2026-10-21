internal import ImageKit
internal import RenderKit

extension LayerStats {
  /// The statistics of `image`, measured the way RenderKit's autostretch does (upper median and
  /// MADN of the finite values, a stride above 64 Ki samples; minimum and maximum).
  ///
  /// A pipeline step after the first gets the statistics of the image it receives, as the Studio
  /// would show for that image — never a process measuring itself (R2).
  static func measured(_ image: AstroImage) -> LayerStats {
    LayerStats(
      channels: image.planes.map { plane in
        let (median, madn) = AutoSTF.medianAndMADN(plane)
        let finite = plane.lazy.filter(\.isFinite)
        return ChannelStats(
          median: median, madn: madn, minimum: Double(finite.min() ?? 0),
          maximum: Double(finite.max() ?? 0))
      })
  }
}
