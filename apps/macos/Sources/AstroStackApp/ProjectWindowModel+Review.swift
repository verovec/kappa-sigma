internal import Foundation
internal import ProjectKit
internal import StackKit

/// The Tri stage's lanes (card 0069).
extension ProjectWindowModel {
  /// What the Tri stage shows: the lane a run waits on; else the lanes this run already
  /// answered, while it goes and after it failed or was cancelled (its hand stays visible, never
  /// a previous stack's); else the last run's lanes read-only (`lastReviewLanes`); else nothing.
  package var reviewLanes: [FrameReviewViewModel] {
    if let paused = run?.paused { return [paused] }
    if let run, run.result == nil, run.isRunning || !run.answered.isEmpty { return run.answered }
    return lastReviewLanes
  }

  /// Rebuilds `lastReviewLanes` when their source changed: this session's finished run, or the
  /// `grades.json` of `latest`, the latest stack (read once, not per render).
  func refreshReviewLanes(latest: ProjectStack?) {
    let source: String?
    let lanes: () -> [FrameReviewViewModel]
    if let run, let result = run.result {
      source = "run:" + run.runID
      lanes = { result.channels.map { FrameReviewViewModel(lane: GradesRecord.Lane($0)) } }
    } else if let folder = folder(), let stack = latest {
      source = "stack:\(stack.id)"
      lanes = {
        // A stack of a build before 0069, or a legacy run, has no record: nothing to show.
        let record = try? GradesRecord.read(from: folder.appendingPathComponent(stack.bundlePath))
        return record?.lanes.map { FrameReviewViewModel(lane: $0) } ?? []
      }
    } else {
      source = nil
      lanes = { [] }
    }
    guard source != lastReviewSource else { return }
    lastReviewSource = source
    lastReviewLanes = lanes()
  }
}
