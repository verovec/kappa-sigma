internal import ProcessKit
package import RenderKit

extension ProcessPanelModel {
  /// The process's handles, when its values sit on the histogram.
  private var handled: (any HistogramHandled.Type)? { type as? any HistogramHandled.Type }

  /// Where the handles sit over the head's histogram, one set per drawn channel.
  package var handles: [STFHandlePositions] {
    guard let handled, let sample else { return [] }
    return handled.handles(params, stats: headStats, channels: sample.planes.count)
  }

  /// A handle of `channel` dropped at `position`: the value it names moves, nothing else.
  package func drag(_ handle: STFHandle, channel: Int, to position: Double) {
    guard let handled,
      let moved = try? handled.dragging(
        handle, channel: channel, to: position, params: params, stats: headStats,
        channels: sample?.planes.count ?? headStats.channels.count)
    else { return }
    replace(moved)
  }

  /// Measures `clipping` for the current values on the current sample (the levels only).
  func measureClipping() {
    guard type == LevelsProcess.self, let sample else {
      if !clipping.isEmpty { clipping = [] }
      return
    }
    let transfer = LevelsTransfer(params, channels: sample.planes.count)
    clipping = sample.clipping { value, channel in transfer.apply(value, channel: channel) }
  }
}
