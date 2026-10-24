internal import Foundation

/// One move of the Studio's history on the undo manager: `steps` back or forward, valid while
/// the head's output is `head` (`nil`: the original), the pipeline column put back at `mark`.
struct StudioMove: Sendable {
  /// How many steps it moves.
  let steps: Int
  /// Back (an undo of steps applied) or forward (a redo).
  let backward: Bool
  /// The head it expects.
  let head: String?
  /// What Edit › Undo / Redo says of it.
  let name: LocalizedStringResource
  /// The column's state once moved, `nil` when the move leaves the column alone.
  let mark: PipelineSidebarModel.Mark?
}
