package import ProjectKit
package import StackKit

/// What a project holds, as the journey reads it: the store's counts plus what later cards learn
/// outside the database.
///
/// The fields beyond `summary` stay at their « unknown » value until a card fills them: the
/// calibration gaps from the plan (0078), the running stacks (0057), the deliverables (0055), the frame review (0069).
nonisolated package struct ProjectFacts: Equatable, Sendable {
  /// Sources, stacks, images, history steps (`ProjectStore.summary`).
  package var summary: ProjectSummary
  /// Light sets with a calibration role nothing covers (`CoverageMatrix.gaps`); `nil` before a
  /// scan.
  package var calibrationGaps: Int?
  /// Stacks being run now.
  package var stacksRunning: Int
  /// Deliverables written by an export.
  package var deliverables: Int
  /// The frames were reviewed (0069); a stack alone says nothing about Tri.
  package var framesReviewed: Bool

  /// The facts of a project with these counts.
  package init(
    summary: ProjectSummary = ProjectSummary(), calibrationGaps: Int? = nil,
    stacksRunning: Int = 0, deliverables: Int = 0, framesReviewed: Bool = false
  ) {
    self.summary = summary
    self.calibrationGaps = calibrationGaps
    self.stacksRunning = stacksRunning
    self.deliverables = deliverables
    self.framesReviewed = framesReviewed
  }

  /// The facts of `summary` with the gaps of the last scan's `coverage` (0078).
  package init(summary: ProjectSummary, coverage: CoverageMatrix?) {
    self.init(summary: summary, calibrationGaps: coverage?.gaps ?? nil)
  }
}
