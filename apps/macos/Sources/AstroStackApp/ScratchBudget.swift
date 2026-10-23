package import Foundation

/// The scratch the next run needs against the room its folder's volume has left (card 0098),
/// as the Stacking stage shows it before Run.
package nonisolated struct ScratchBudget: Equatable, Sendable {
  /// The largest peak among the queued runs (each removes its work folder when it ends).
  package var neededBytes: Int64
  /// The bytes left on the scratch volume; `nil` when the volume does not say.
  package var roomBytes: Int64?
  /// The scratch folder runs go to.
  package var folder: URL

  /// A budget of `neededBytes` against `roomBytes` in `folder`.
  package init(neededBytes: Int64, roomBytes: Int64?, folder: URL) {
    self.neededBytes = neededBytes
    self.roomBytes = roomBytes
    self.folder = folder
  }

  /// The run fits, or the volume does not say (nothing is refused on a guess).
  package var fits: Bool { roomBytes.map { neededBytes <= $0 } ?? true }

  /// Whole gigabytes, rounded up: the need is never shown smaller than it is.
  package static func gigabytesUp(_ bytes: Int64) -> Int {
    Int((bytes + 999_999_999) / 1_000_000_000)
  }

  /// Whole gigabytes, rounded down: the room is never shown larger than it is.
  package static func gigabytesDown(_ bytes: Int64) -> Int {
    Int(bytes / 1_000_000_000)
  }
}
