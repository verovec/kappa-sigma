/// What the next run redoes (card 0100), as the Stacking stage says it before Run: every checked
/// night is calibrated, registered and graded again — a run reuses nothing of an earlier stack
/// (PO 2026-10-22 « restack all »).
package nonisolated struct RestackPlan: Equatable, Sendable {
  /// The capture nights with a checked set, each once whatever the object.
  package var nights: Int
  /// The checked lights.
  package var frames: Int
  /// The capture folders no earlier stack was built from; `nil` before the first stack.
  package var added: Int?

  /// A plan of `nights` nights and `frames` lights, `added` folders new since the last stack.
  package init(nights: Int, frames: Int, added: Int?) {
    self.nights = nights
    self.frames = frames
    self.added = added
  }

  /// The plan of the checked `series` over the capture folders `nightSourceIDs`, against the
  /// folders of the last stack (`nil` without one); `nil` when nothing is checked or not scanned.
  @MainActor
  package init?(
    series: StackingStageModel, nightSourceIDs: [Int64], lastStackSourceIDs: [Int64]?
  ) {
    guard !series.scopes.isEmpty else { return nil }
    // Two objects shot the same night are one capture night. An empty key is a single-night
    // scan (`FrameSet.group`), or the undated lights of a longer one, counted as one night.
    nights = Set(series.checkedNights.map(\.night)).count
    frames = series.scopes.map(\.lights).reduce(0, +)
    added = lastStackSourceIDs.map { stacked in
      Set(nightSourceIDs).subtracting(stacked).count
    }
  }
}
