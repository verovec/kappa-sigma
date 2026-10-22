package import Foundation

/// `grades.json` (card 0069): what grading decided on every lane of a run and what the user
/// changed at the review, written beside the bundle so the Tri stage can show the last run's
/// verdicts after the work folder is gone.
package struct GradesRecord: Codable, Equatable, Sendable {
  /// One lane's grades and review.
  package struct Lane: Codable, Equatable, Sendable {
    /// The lane (filter).
    package var lane: String
    /// The run paused on this lane and the user answered (even with no change).
    package var reviewed: Bool
    /// What the user changed; nil when the lane was not reviewed.
    package var decision: FrameDecision?
    /// The registration reference as `FrameGrade.index`, when Siril's sequence said.
    package var reference: Int?
    /// Each frame's capture night, parallel to `grades`.
    package var nights: [String]
    /// One grade per input frame, as stacked (the user's decisions applied).
    package var grades: [FrameGrade]
    /// Why the lane failed, when it did: a failed lane never reads back as an empty one.
    package var error: String?
    /// The reference the user pinned (card 0096), when one was; `reference` is the one applied.
    package var pinnedReference: Int?

    /// The lane of `outcome`.
    package init(_ outcome: ChannelOutcome) {
      lane = outcome.filter
      reviewed = outcome.frameDecision != nil
      decision = outcome.frameDecision
      reference = outcome.reference
      nights = outcome.frameNights
      grades = outcome.grades
      error = outcome.error
      pinnedReference = outcome.referencePin
    }

    private enum CodingKeys: String, CodingKey {
      case lane, reviewed, decision, reference, nights, grades, error
      case pinnedReference = "pinned_reference"
    }
  }

  /// The file's name, beside `bundle.json`.
  package static let fileName = "grades.json"

  /// The format version.
  package var version = 1
  package var runID: String
  /// The lanes in run order.
  package var lanes: [Lane]

  private enum CodingKeys: String, CodingKey {
    case version, lanes
    case runID = "run_id"
  }

  /// The record of the channels of `result`.
  package init(result: PreprocessResult) {
    runID = result.runID
    lanes = result.channels.map(Lane.init)
  }

  /// Writes `folder/grades.json`, replaced atomically; snake_case keys, as the legacy records.
  package func write(to folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(
      to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }

  /// The record in `folder`.
  package static func read(from folder: URL) throws -> Self {
    try JSONDecoder().decode(
      Self.self, from: Data(contentsOf: folder.appendingPathComponent(fileName)))
  }
}
