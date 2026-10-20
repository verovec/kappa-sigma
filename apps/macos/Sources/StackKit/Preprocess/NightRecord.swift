/// One night inside a multi-night channel (`GroupResult`): its geometry against the anchor night
/// and what it contributed to the stack.
package struct NightRecord: Equatable, Sendable {
  package var session: String
  package var frames: Int
  package var stacked = 0
  package var rejected = 0
  /// Median field rotation against the anchor canvas, in degrees.
  package var rotationDegrees: Double?
  /// Median footprint overlap with the anchor canvas, 0…1.
  package var overlapFraction: Double?

  /// A night of `frames` frames.
  package init(session: String, frames: Int) {
    self.session = session
    self.frames = frames
  }
}

extension GroupedChannelStacker {
  /// Each night's registration telemetry; a lone group is self-anchored and records none.
  static func nights(_ merge: Merge, review: RegistrationReview) -> [NightRecord] {
    merge.nights.enumerated().map { index, night in
      var record = NightRecord(session: night.key.session, frames: night.count)
      if merge.nights.count > 1, index < review.groups.count {
        record.rotationDegrees = review.groups[index].rotationDegrees
        record.overlapFraction = review.groups[index].overlapFraction
      }
      return record
    }
  }

  /// Folds the grading back onto each night (`recordGroupContributions`).
  static func contributions(_ nights: [NightRecord], spans: [Range<Int>], grades: [FrameGrade])
    -> [NightRecord]
  {
    zip(nights, spans).map { night, span in
      var record = night
      let graded = span.filter { $0 < grades.count }.map { grades[$0] }
      record.rejected = graded.count(where: \.rejected)
      record.stacked = graded.count { !$0.rejected && $0.fwhm > 0 }
      return record
    }
  }
}
