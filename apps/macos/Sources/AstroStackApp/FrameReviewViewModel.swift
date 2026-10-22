package import Foundation
internal import Observation
package import StackKit

/// One lane at the Tri stage (card 0069): its grades as rows, the user's keep / reject toggles,
/// the sort the blink follows, and Continue, which hands the run exactly the toggles as a
/// `FrameDecision` (values shown = values applied, R2).
///
/// Live over a paused run (`PreprocessEvent.Frames`); read-only over `grades.json`.
@Observable
package final class FrameReviewViewModel {
  /// One frame as the table shows it; nonisolated so its key paths sort and compare anywhere.
  nonisolated package struct Row: Identifiable, Equatable, Sendable {
    /// `FrameGrade.index`, 1-based in the sequence.
    package let index: Int
    package let night: String
    package let path: String
    package let fwhm: Double
    package let roundness: Double
    package let starCount: Int
    package let background: Double
    package let trailDetected: Bool
    package let trailScore: Double
    package let shiftX: Double
    package let shiftY: Double
    /// Siril registered it (an unregistered frame cannot be stacked).
    package let isRegistered: Bool
    /// The grader's verdict, before the user.
    package let autoRejected: Bool
    /// The grader's reason, empty when it kept the frame.
    package let autoReason: String
    /// The quick look, while the run's work folder lives.
    package let thumbnail: URL?
    /// Kept as the user left it.
    package var isKept: Bool

    package var id: Int { index }
    /// The user went against the grader.
    package var isOverridden: Bool { isRegistered && isKept == autoRejected }
    /// The reason shown: the grader's, or the user's with the grader's kept as provenance.
    package var reason: String {
      guard isOverridden else { return autoReason }
      if isKept { return ChannelGrading.keptUserPrefix + autoReason }
      return autoReason.isEmpty
        ? ChannelGrading.userReason : ChannelGrading.userExcludedPrefix + autoReason
    }
    /// The registration shift's length, in pixels.
    package var shift: Double { (shiftX * shiftX + shiftY * shiftY).squareRoot() }
  }

  package let lane: String
  /// The registration reference as `Row.index`, shown, not editable here (card 0096).
  package let elected: Int?
  /// Why the lane failed, read back from the record; nil for a lane that stacked.
  package let error: String?
  package private(set) var rows: [Row]
  /// A run waits on this lane: toggles count and Continue is offered.
  package private(set) var isLive: Bool
  /// Continue was pressed: the run goes on with this hand (shown until the run's result lands).
  package private(set) var isAnswered = false
  /// The table's sort, which the blink follows.
  package var sortOrder: [KeyPathComparator<Row>]
  /// The frame shown in the blink panel, by `Row.index`.
  package private(set) var current: Int?
  private let onContinue: (FrameDecision) -> Void

  /// A live lane: the run waits for `onContinue`.
  package init(frames: PreprocessEvent.Frames, onContinue: @escaping (FrameDecision) -> Void) {
    lane = frames.lane
    elected = frames.elected
    error = nil
    rows = zip(frames.grades.indices, frames.grades).map { position, grade in
      Row(
        grade, night: frames.nights.indices.contains(position) ? frames.nights[position] : "",
        thumbnail: frames.thumbnails.indices.contains(position)
          ? frames.thumbnails[position].map { URL(fileURLWithPath: $0) } : nil)
    }
    isLive = true
    self.onContinue = onContinue
    sortOrder = [KeyPathComparator(\.index)]
    current = rows.first { $0.thumbnail != nil }?.index
  }

  /// A lane read back from `grades.json`: the verdicts as stacked, nothing to answer.
  package init(lane: GradesRecord.Lane) {
    self.lane = lane.lane
    elected = lane.reference
    error = lane.error
    rows = zip(lane.grades.indices, lane.grades).map { position, grade in
      Row(grade, night: lane.nights.indices.contains(position) ? lane.nights[position] : "")
    }
    isLive = false
    onContinue = { _ in }
    sortOrder = [KeyPathComparator(\.index)]
  }

  // MARK: - Sort and blink

  /// The rows in `sortOrder`, the unregistered ones last in sequence order.
  package var sortedRows: [Row] {
    rows.filter(\.isRegistered).sorted(using: sortOrder) + rows.filter { !$0.isRegistered }
  }

  /// The rows the blink cycles through: those with a thumbnail, in the sort's order.
  package var blinkRows: [Row] { sortedRows.filter { $0.thumbnail != nil } }

  /// The row shown, if any.
  package var currentRow: Row? { rows.first { $0.index == current } }

  /// Shows `index` (a row chosen in the table).
  package func select(_ index: Int?) {
    current = index
  }

  /// The next frame in the sort, wrapping around.
  package func blinkNext() {
    step(1)
  }

  /// The previous frame in the sort, wrapping around.
  package func blinkPrevious() {
    step(-1)
  }

  private func step(_ offset: Int) {
    let order = blinkRows.map(\.index)
    guard !order.isEmpty else { return }
    guard let current, let position = order.firstIndex(of: current) else {
      self.current = order[0]
      return
    }
    self.current = order[(position + offset + order.count) % order.count]
  }

  // MARK: - Decisions

  /// Keeps / rejects frame `index` the other way round; nothing for an unregistered frame or a
  /// read-only lane.
  package func toggle(_ index: Int) {
    guard let row = rows.first(where: { $0.index == index }) else { return }
    set(index, kept: !row.isKept)
  }

  /// Keeps frame `index`.
  package func keep(_ index: Int) {
    set(index, kept: true)
  }

  /// Rejects frame `index`.
  package func reject(_ index: Int) {
    set(index, kept: false)
  }

  private func set(_ index: Int, kept: Bool) {
    guard isLive, let position = rows.firstIndex(where: { $0.index == index }),
      rows[position].isRegistered
    else { return }
    rows[position].isKept = kept
  }

  /// Exactly the toggles against the grader, as the run applies them.
  package var decision: FrameDecision {
    FrameDecision(
      exclude: rows.filter { $0.isOverridden && !$0.isKept }.map(\.index),
      forceKeep: rows.filter { $0.isOverridden && $0.isKept }.map(\.index))
  }

  /// Frames that will be stacked.
  package var keptCount: Int { rows.count { $0.isRegistered && $0.isKept } }

  /// Continue is offered: the run waits and Siril's stack minimum holds.
  package var canContinue: Bool { isLive && keptCount >= Grader.stackMinimum }

  /// Hands the run the decision, once; the lane turns read-only.
  package func continueStacking() {
    guard canContinue else { return }
    isLive = false
    isAnswered = true
    onContinue(decision)
  }

  // MARK: - Metrics

  /// `metric` of the registered frames in `bins` equal-width bins over its range, as one
  /// histogram channel (`HistogramView(bins:)`); the maximum lands in the last bin.
  package func histogram(_ metric: KeyPath<Row, Double>, bins: Int = 32) -> [[Int]] {
    let values = rows.filter(\.isRegistered).map { $0[keyPath: metric] }
    var counts = [Int](repeating: 0, count: max(bins, 1))
    guard let low = values.min(), let high = values.max() else { return [counts] }
    let width = high - low
    for value in values {
      let bin = width > 0 ? Int((value - low) / width * Double(counts.count)) : 0
      counts[min(bin, counts.count - 1)] += 1
    }
    return [counts]
  }
}

extension FrameReviewViewModel.Row {
  /// A row of `grade`: the grader's verdict split from the user's, so a read-back lane shows
  /// who decided (`user`, `kept (user) — was: …`).
  fileprivate init(_ grade: FrameGrade, night: String, thumbnail: URL? = nil) {
    index = grade.index
    self.night = night
    path = grade.path
    fwhm = grade.fwhm
    roundness = grade.roundness
    starCount = grade.starCount
    background = grade.background
    trailDetected = grade.trailDetected
    trailScore = grade.trailScore
    shiftX = grade.shiftX
    shiftY = grade.shiftY
    isRegistered = grade.fwhm > 0
    self.thumbnail = thumbnail
    if grade.rejectReason == ChannelGrading.userReason {
      (autoRejected, autoReason, isKept) = (false, "", false)
    } else if grade.rejectReason.hasPrefix(ChannelGrading.userExcludedPrefix) {
      // The grader had restored it (stack minimum); its wording stays.
      let reason = String(grade.rejectReason.dropFirst(ChannelGrading.userExcludedPrefix.count))
      (autoRejected, autoReason, isKept) = (false, reason, false)
    } else if grade.rejectReason.hasPrefix(ChannelGrading.keptUserPrefix) {
      let reason = String(grade.rejectReason.dropFirst(ChannelGrading.keptUserPrefix.count))
      (autoRejected, autoReason, isKept) = (true, reason, true)
    } else {
      (autoRejected, autoReason, isKept) = (grade.rejected, grade.rejectReason, !grade.rejected)
    }
  }
}
