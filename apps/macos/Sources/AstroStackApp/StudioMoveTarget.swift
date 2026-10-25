/// What a workspace's moves are registered with, one per direction and history (card 0117):
/// the tag the history's buttons recognise, and a target the Studio drops apart from the
/// pipeline column's edits.
package final class StudioMoveTarget {
  /// The workspace whose history it moves.
  weak var workspace: StudioWorkspaceModel?
  /// Its moves go back (undo applied steps) or forward (redo them).
  let backward: Bool
  /// The history they move.
  let selection: StudioSelection

  init(workspace: StudioWorkspaceModel, backward: Bool, selection: StudioSelection) {
    self.workspace = workspace
    self.backward = backward
    self.selection = selection
  }
}

extension StudioWorkspaceModel {
  /// The target of the moves `backward` (or forward) on the history of `selection`.
  func moveTarget(backward: Bool, in selection: StudioSelection) -> StudioMoveTarget {
    if let target = moveTargets.first(where: {
      $0.backward == backward && $0.selection == selection
    }) {
      return target
    }
    let target = StudioMoveTarget(workspace: self, backward: backward, selection: selection)
    moveTargets.append(target)
    return target
  }
}
