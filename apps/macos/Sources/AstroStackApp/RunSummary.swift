package import Foundation
package import StackKit

/// What a finished run says about each channel, as the Run panel words it: the frames stacked,
/// the trail mask, the error of a channel that failed (the run goes on without it).
package nonisolated enum RunSummary {
  /// One line per channel, in the run's order.
  package static func channels(_ result: PreprocessResult, locale: Locale? = nil)
    -> [LocalizedStringResource]
  {
    result.channels.map { channel in
      if let error = channel.error {
        return .app("\(channel.filter): not stacked — \(error)", locale: locale)
      }
      return .app(
        "\(channel.filter): \(channel.stackedFrames) of \(channel.inputFrames) frames stacked",
        locale: locale)
    }
  }

  /// The trail mask of each channel that ran it (`k` > 0), naming the channel.
  package static func trailMasks(_ result: PreprocessResult, locale: Locale? = nil)
    -> [LocalizedStringResource]
  {
    result.channels.compactMap { channel in
      guard let mask = channel.trailMask else { return nil }
      let (trails, hit, frames) = (mask.segments, mask.framesWithTrails, mask.frames)
      return .app(
        "\(channel.filter) trail mask: \(trails) trails on \(hit) of \(frames) frames",
        locale: locale)
    }
  }
}
