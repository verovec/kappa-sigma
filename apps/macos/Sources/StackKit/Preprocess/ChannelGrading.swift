/// Grades one channel from its calibrated sequence's `.seq` (`gradeChannel`).
///
/// Frames Siril could not register (all-zero metrics) are rejected up front and absent from the
/// registered numbering `r_<seq>_00001…`; the rejected frames are returned as 1-based indices in
/// that numbering, as `unselect` wants them.
package enum ChannelGrading {
  /// What grading decided.
  package struct Outcome: Equatable, Sendable {
    /// One grade per input frame, in sequence order.
    package var grades: [FrameGrade]
    /// 1-based indices in the registered sequence to leave out of the stack.
    package var rejectedRegistered: [Int]
    /// Frames present in the registered sequence.
    package var registeredCount: Int
  }

  package static let unregisteredReason = "could not register (too few/elongated stars)"
  package static let wheelTransitionReason = "filter-wheel transition (off-brightness first frame)"

  /// Grades `sequence`; `trail` probes the calibrated frame at a 0-based index (nil: unreadable;
  /// it may throw to stop, as on cancellation),
  /// `preReject` carries upstream rejections by 0-based index, `spans` scope the relative rules.
  package static func grade(
    _ sequence: SirilSequence, frames: [CaptureFrame], settings: PreprocessSettings,
    preReject: [Int: String] = [:], spans: [Range<Int>] = [],
    trail: (Int) throws -> (detected: Bool, score: Double)? = { _ in nil }
  ) rethrows -> Outcome {
    var grades = try sequence.metrics.enumerated().map { index, metric in
      var grade = FrameGrade(
        index: index + 1, path: index < frames.count ? frames[index].path : "", sequence: metric)
      if metric.fwhm <= 0 {
        grade.rejected = true
        grade.rejectReason = unregisteredReason
        return grade
      }
      if let reason = preReject[index] {
        (grade.rejected, grade.rejectReason) = (true, reason)
      } else if settings.dropWheelTransition, index < frames.count, frames[index].wheelTransition {
        (grade.rejected, grade.rejectReason) = (true, wheelTransitionReason)
      }
      if let probe = try trail(index) { (grade.trailDetected, grade.trailScore) = probe }
      return grade
    }
    Grader.grade(&grades, spans: spans, options: settings.grading)
    var outcome = Outcome(grades: grades, rejectedRegistered: [], registeredCount: 0)
    for grade in grades where grade.fwhm > 0 {
      outcome.registeredCount += 1
      if grade.rejected { outcome.rejectedRegistered.append(outcome.registeredCount) }
    }
    return outcome
  }
}
