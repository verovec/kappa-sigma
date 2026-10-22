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

    /// An outcome from its parts (a test replays a decision on recorded grades).
    package init(grades: [FrameGrade], rejectedRegistered: [Int], registeredCount: Int) {
      self.grades = grades
      self.rejectedRegistered = rejectedRegistered
      self.registeredCount = registeredCount
    }
  }

  package static let unregisteredReason = "could not register (too few/elongated stars)"
  package static let wheelTransitionReason = "filter-wheel transition (off-brightness first frame)"
  /// The reason of a frame the user rejected at the review (card 0069).
  package static let userReason = "user"
  /// The reason prefix of a frame the user rejected that the grader had restored (stack
  /// minimum); the grader's wording follows, so nothing of the history is lost.
  package static let userExcludedPrefix = "user — was: "
  /// The reason prefix of a frame the user kept despite the grader; the grader's reason follows.
  package static let keptUserPrefix = "kept (user) — was: "

  /// Applies the user's `decision` to `outcome` (card 0069).
  ///
  /// An excluded registered frame is rejected with reason `user` (the grader's wording kept
  /// after « was: » when it had one), a force-kept auto-rejected one is restored with the grader's
  /// reason kept as provenance; an unregistered frame cannot be kept. The registered rejection
  /// list is rebuilt, as `unselect` wants it.
  package static func apply(_ decision: FrameDecision, to outcome: inout Outcome) {
    for index in outcome.grades.indices where outcome.grades[index].fwhm > 0 {
      let position = outcome.grades[index].index
      if decision.exclude.contains(position), !outcome.grades[index].rejected {
        let previous = outcome.grades[index].rejectReason
        outcome.grades[index].rejected = true
        outcome.grades[index].rejectReason =
          previous.isEmpty ? userReason : userExcludedPrefix + previous
      } else if decision.forceKeep.contains(position), outcome.grades[index].rejected {
        outcome.grades[index].rejected = false
        outcome.grades[index].rejectReason = keptUserPrefix + outcome.grades[index].rejectReason
      }
    }
    renumber(&outcome)
  }

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
    renumber(&outcome)
    return outcome
  }

  /// Counts the registered frames and lists the rejected ones in the registered numbering.
  private static func renumber(_ outcome: inout Outcome) {
    outcome.registeredCount = 0
    outcome.rejectedRegistered = []
    for grade in outcome.grades where grade.fwhm > 0 {
      outcome.registeredCount += 1
      if grade.rejected { outcome.rejectedRegistered.append(outcome.registeredCount) }
    }
  }
}
