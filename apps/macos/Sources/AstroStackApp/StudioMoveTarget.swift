/// What a workspace's moves are registered with, one per direction (card 0117): the tag the
/// buttons recognise, and a target the Studio drops apart from the pipeline column's edits.
package final class StudioMoveTarget {
  /// The workspace whose history it moves.
  weak var workspace: StudioWorkspaceModel?
}
