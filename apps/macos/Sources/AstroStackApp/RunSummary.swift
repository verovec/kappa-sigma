package import Foundation
package import StackKit

/// What a finished run says about each channel, as the Run panel words it: the frames stacked,
/// the trail mask, the error of a channel that failed (the run goes on without it).
package nonisolated enum RunSummary {
  /// One line per channel, in the run's order.
  package static func channels(_ result: PreprocessResult, locale: Locale? = nil)
    -> [LocalizedStringResource]
  {
    let format = AstroFormat(locale: locale ?? Locale.autoupdatingCurrent)
    return result.channels.map { channel in
      if let error = channel.error {
        return .app("\(channel.filter): not stacked — \(error)", locale: locale)
      }
      let (stacked, of) = (
        format.integer(channel.stackedFrames), format.frames(channel.inputFrames)
      )
      return .app("\(channel.filter): \(stacked) of \(of) stacked", locale: locale)
    }
  }

  /// The trail mask of each channel that ran it (`k` > 0), naming the channel.
  package static func trailMasks(_ result: PreprocessResult, locale: Locale? = nil)
    -> [LocalizedStringResource]
  {
    let format = AstroFormat(locale: locale ?? Locale.autoupdatingCurrent)
    return result.channels.compactMap { channel in
      guard let mask = channel.trailMask else { return nil }
      let trails = format.integer(mask.segments)
      let (hit, of) = (format.integer(mask.framesWithTrails), format.frames(mask.frames))
      return .app(
        "\(channel.filter) trail mask: \(trails) trails on \(hit) of \(of)", locale: locale)
    }
  }
}
