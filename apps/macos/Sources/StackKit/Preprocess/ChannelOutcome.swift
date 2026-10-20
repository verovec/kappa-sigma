/// One stacked channel (`ChannelResult`): its selection, grades and master, or why it failed.
///
/// A failed channel is reported and the run continues without it.
package struct ChannelOutcome: Equatable, Sendable {
  package var object: String
  /// The channel's filter (lane).
  package var filter: String
  package var exposureMs: Int
  package var inputFrames: Int
  package var selection: CalibrationSelection
  package var grades: [FrameGrade] = []
  package var stackedFrames = 0
  /// The linear master, `<out>/master_<tag>.fits`, once written.
  package var masterPath: String?
  /// Channel-scoped warnings, already surfaced live.
  package var warnings: [String] = []
  /// Why the channel failed; nil when it produced a master.
  package var error: String?

  /// A channel about to be processed.
  package init(_ set: FrameSet, filter: String, selection: CalibrationSelection) {
    object = set.key.object
    self.filter = filter
    exposureMs = set.key.exposureMs
    inputFrames = set.count
    self.selection = selection
  }

  /// The frames kept and rejected, with reasons (`selection.json`).
  package var kept: [String] { grades.filter { !$0.rejected }.map(\.path) }

  /// The grading warnings (`gradeWarnings`); empty on a healthy channel.
  ///
  /// Frames Siril dropped, and frames restored to reach the stack minimum.
  static func gradingWarnings(filter: String, grades: [FrameGrade], registered: Int, survivors: Int)
    -> [String]
  {
    var out: [String] = []
    if registered < grades.count {
      out.append(
        "\(filter): only \(registered)/\(grades.count) frames registered — "
          + "\(grades.count - registered) dropped (no stars matched)")
    }
    let restored = grades.filter { !$0.rejected }.compactMap { grade -> String? in
      guard grade.rejectReason.hasPrefix(Grader.keptStackMinimumPrefix) else { return nil }
      return String(grade.rejectReason.dropFirst(Grader.keptStackMinimumPrefix.count))
    }
    if !restored.isEmpty {
      out.append(
        "\(filter): stacking \(survivors) survivor(s) — \(restored.count) kept despite: "
          + restored.joined(separator: "; "))
    }
    return out
  }
}
