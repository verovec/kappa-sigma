internal import Foundation

extension Preprocessor {
  /// The review hook of a run (card 0069): thumbnails of the registered frames under
  /// `work/frames/<lane>/`, the `frames` event with its gate, then the wait for the decision.
  ///
  /// The journal says the run is waiting; cancelling the run releases the gate.
  func frameReviewHook(work: URL, emitter: RunEmitter) -> ChannelStacker.FrameReviewHook {
    let preview = tools.preview
    return { context in
      let folder = work.appendingPathComponent("frames", isDirectory: true)
        .appendingPathComponent(ChannelTag.sanitize(context.lane), isDirectory: true)
      let thumbnails = try Self.thumbnails(context, in: folder, preview: preview) {
        emitter.line($0)
      }
      let gate = FrameReviewGate(lane: context.lane)
      emitter.frames(
        PreprocessEvent.Frames(
          lane: context.lane, grades: context.grades, spans: context.spans,
          nights: context.nights, elected: context.elected, thumbnails: thumbnails, gate: gate))
      let registered = context.grades.count { $0.fwhm > 0 }
      emitter.line(
        "▶ frame review: \(context.lane) paused after grading (\(registered) registered frames) — "
          + "waiting for the user")
      let decision = try await gate.decision()
      emitter.line(
        "frame review: \(context.lane) resumed — \(decision.exclude.count) rejected by hand, "
          + "\(decision.forceKeep.count) kept by hand")
      return decision
    }
  }

  /// Thumbnails are journaled every this many frames (a 350-frame lane takes a while).
  static let thumbnailProgressEvery = 25

  /// A quick look per registered frame (`NNNNN.png` by `FrameGrade.index`), nil where the frame
  /// was dropped or the render failed — a failure is a `⚠` line, never silent (R2); a cancelled
  /// run stops between frames.
  static func thumbnails(
    _ context: FrameReviewContext, in folder: URL,
    preview: @Sendable (URL, URL) throws -> Void, report: (String) -> Void
  ) throws -> [String?] {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let total = context.registeredFrames.count { $0 != nil }
    var done = 0
    return try zip(context.grades, context.registeredFrames).map { grade, fits in
      try Task.checkCancellation()
      guard let fits else { return nil }
      done += 1
      if done % thumbnailProgressEvery == 0 || done == total {
        report("frame review: previews \(done)/\(total) of \(context.lane)")
      }
      let png = folder.appendingPathComponent(String(format: "%05d.png", grade.index))
      do {
        try preview(fits, png)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        report("⚠ frame review: no preview for frame \(grade.index) of \(context.lane): \(error)")
        return nil
      }
      return png.path
    }
  }
}
