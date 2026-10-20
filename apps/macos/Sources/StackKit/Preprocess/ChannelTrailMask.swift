package import Foundation
internal import ImageKit

/// A channel's registered frames through the cross-frame trail mask before the stack
/// (`maskChannelTrails`, `summarizeTrailMask`).
///
/// Every registered frame is masked, graded out or not (a larger sample makes the median more
/// robust). While 3·n whole frames fit the budget the pass runs in memory, otherwise it streams
/// against a budget-sized basis. Frames that changed are rewritten in place, headers kept.
package enum ChannelTrailMask {
  /// What the mask did, in the legacy record and wording.
  package struct Outcome: Equatable, Sendable {
    package var summary: TrailMaskSummary
    /// `streamed, N-frame basis under a B GiB memory budget`, nil in memory.
    package var mode: String?
    /// The frames' size, for the note's share.
    package var width: Int
    package var height: Int

    /// The channel note.
    package var note: String {
      ChannelTrailMask.note(summary, width: width, height: height, mode: mode)
    }
  }

  /// Masks `files` with `k`; nil under five frames.
  ///
  /// Off the caller's actor: minutes of CPU on a large channel.
  @concurrent
  package static func mask(_ files: [URL], k: Double, budget: Int64) async throws -> Outcome? {
    guard files.count >= TrailMask.minimumFrames, k > 0 else { return nil }
    let header = try FITSFile.read(at: files[0]).header
    let (width, height) = (header.int("NAXIS1") ?? 0, header.int("NAXIS2") ?? 0)
    let frameBytes = Int64(width) * Int64(height) * 4 * Int64(header.int("NAXIS3") ?? 1)
    let plan = TrailMaskBudget.plan(frames: files.count, frameBytes: frameBytes, budget: budget)
    let report: TrailMaskReport
    var mode: String?
    if plan.streamed {
      report = try await TrailMask.maskStreamed(files, k: k, basis: plan.basis)
      mode =
        "streamed, \(plan.basis)-frame basis under a "
        + "\(String(format: "%.1f", Double(budget) / Double(1 << 30))) GiB memory budget"
    } else {
      report = try await inMemory(files, k: k, width: width, height: height)
    }
    var summary = report.summary
    summary.frames = files.count
    return Outcome(summary: summary, mode: mode, width: width, height: height)
  }

  /// The whole channel resident: read, mask, rewrite the frames that changed.
  private static func inMemory(_ files: [URL], k: Double, width: Int, height: Int) async throws
    -> TrailMaskReport
  {
    var sources: [(FITSFile, AstroImage)] = []
    var frames: [[[Float]]] = []
    for url in files {
      try Task.checkCancellation()
      let file = try FITSFile.read(at: url)
      let image = try file.image()
      // The planes move out of the image so the mask mutates them in place, never a copy.
      frames.append(image.planes)
      image.planes = []
      sources.append((file, image))
    }
    let report = try await TrailMask.mask(&frames, width: width, height: height, k: k)
    for (index, record) in report.frames.enumerated() where record.maskedPixels > 0 {
      let (file, image) = sources[index]
      image.planes = frames[index]
      try file.write(image, to: files[index])
      image.planes = []
    }
    return report
  }

  /// The channel note (`summarizeTrailMask`).
  package static func note(_ summary: TrailMaskSummary, width: Int, height: Int, mode: String?)
    -> String
  {
    let share =
      100 * Double(summary.maskedPixels) / Double(max(1, summary.frames * width * height))
    var text =
      "cross-frame trail mask: cleaned \(summary.maskedPixels) pixels "
      + "(\(String(format: "%.2f", share))%) across \(summary.frames) frames — "
      + "\(summary.segments) trail segment(s) in \(summary.framesWithTrails) frame(s), "
      + "\(summary.rejected) candidate(s) rejected as fixed pattern"
    if summary.recurring > 0 { text += ", \(summary.recurring) recurring corridor(s) repaired" }
    if summary.saturatedPixels > 0 {
      text +=
        ", \(summary.saturatedPixels) sensor-saturated core px repaired from unsaturated nights"
    }
    if let mode { text += " (\(mode))" }
    return text
  }
}
