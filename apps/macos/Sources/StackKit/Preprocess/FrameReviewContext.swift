package import Foundation

/// What a graded lane hands to the frame review (card 0069) before its stack: the grades as the
/// grader left them, the nights, the elected reference and the registered frame of each grade.
package struct FrameReviewContext: Sendable {
  /// The lane (filter).
  package var lane: String
  /// One grade per input frame, in sequence order.
  package var grades: [FrameGrade]
  /// The nights as positions in `grades`; one span for a single night.
  package var spans: [Range<Int>]
  /// Each frame's capture night, parallel to `grades`.
  package var nights: [String]
  /// The reference as `FrameGrade.index`, when the sequence says.
  package var elected: Int?
  /// The registered frame per grade, nil for a frame Siril dropped.
  package var registeredFrames: [URL?]

  /// A lane's review context.
  package init(
    lane: String, grades: [FrameGrade], spans: [Range<Int>], nights: [String], elected: Int?,
    registeredFrames: [URL?]
  ) {
    self.lane = lane
    self.grades = grades
    self.spans = spans
    self.nights = nights
    self.elected = elected
    self.registeredFrames = registeredFrames
  }
}
