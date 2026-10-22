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
        handle, channel: channel, to: position, params: params, stats: headStats)
    else { return }
    replace(moved)
  }

  /// What the levels send to black and white on the head's sample, per channel (measured and
  /// shown, never applied); none for another process.
  package var clipping: [HeadSample.Clipping] {
    guard type == LevelsProcess.self, let sample else { return [] }
    let channels = sample.planes.count
    let params = params
    return sample.clipping { value, channel in
      LevelsProcess.transfer(value, channel: channel, channels: channels, params: params)
    }
  }
}
