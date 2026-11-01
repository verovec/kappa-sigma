/// A history operation that cannot be done.
package enum HistoryError: Error, Equatable, Sendable {
  /// No applied step has this index.
  case noStep(Int)
  /// No applied step.
  case nothingToUndo
  /// No undone step.
  case nothingToRedo
  /// No snapshot has this name.
  case unknownSnapshot(String)
  /// A snapshot already has this name.
  case duplicateSnapshot(String)
  /// The history moved while the host tool `processID` ran: its step would overwrite the move.
  case movedDuring(String)
  /// The history's manifest cannot be read back: why.
  case unreadable(String)
  /// No version has this id (card 0156).
  case unknownVersion(String)
  /// The version starts after the last applied step (undone since): redo first (card 0156).
  case versionOutOfReach(String)
}
