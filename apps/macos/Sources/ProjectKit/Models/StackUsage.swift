/// What the retention policy reads of a closed project (card 0114): its stacks, their export
/// counts and the stack chosen for the Studio.
package struct StackUsage: Equatable, Sendable {
  /// Every stack, oldest first (paused runs included: the policy skips them).
  package let stacks: [ProjectStack]
  /// Export count by stack id, for the stacks that have one.
  package let exportCounts: [Int64: Int]
  /// The stack the user chose for the Studio, if any.
  package let chosenStackID: Int64?
  /// The stacks the user chose to keep from the launch sheet.
  package let keptStackIDs: Set<Int64>
  /// When openings started being recorded (0008's `applied_at`, Unix ms): a use of every stack.
  package let since: Int64

  /// A reading.
  package init(
    stacks: [ProjectStack], exportCounts: [Int64: Int], chosenStackID: Int64?,
    keptStackIDs: Set<Int64> = [], since: Int64 = 0
  ) {
    self.stacks = stacks
    self.exportCounts = exportCounts
    self.chosenStackID = chosenStackID
    self.keptStackIDs = keptStackIDs
    self.since = since
  }

  /// The stacks the policy never offers: the chosen one and the kept ones.
  package var protected: Set<Int64> {
    keptStackIDs.union(chosenStackID.map { [$0] } ?? [])
  }
}
