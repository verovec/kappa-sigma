package import RenderKit

/// A process whose values sit as handles on the head's histogram (card 0089): the panel draws
/// them over the input histogram (values on the axis) and turns a drag into new values.
///
/// R2: a drag sets the values the panel shows, nothing else; the histogram is measured and shown,
/// never read by the process.
package protocol HistogramHandled: ImageProcess {
  /// Where the handles of `params` sit, one set per drawn channel (none when the current values
  /// have no handles), for an image of `channels` planes with `stats`.
  static func handles(_ params: ParamSet, stats: LayerStats, channels: Int)
    -> [STFHandlePositions]

  /// `params` after `handle` of `channel` is dropped at `position` (a value, 0…1).
  static func dragging(
    _ handle: STFHandle, channel: Int, to position: Double, params: ParamSet, stats: LayerStats
  ) throws -> ParamSet
}
