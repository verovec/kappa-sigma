package import Foundation

/// The Studio's moves on the window's undo manager (card 0087): an Apply — from the button or
/// Edit › Apply Process — registers its undo, which registers the redo, and so on.
///
/// The actions are discardable (the history is on disk at once: a titled project is never marked
/// edited by them), removed when their workspace is replaced, and a move made from another
/// stage brings the Studio into view first, never moving its history out of sight.
package enum StudioUndo {
  /// Applies the panel of `model` and registers the move with `undoManager` when a step was
  /// added.
  package static func apply(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    let before = model.studio.steps.count
    try? model.apply()
    guard model.studio.steps.count > before else { return }
    model.undoManager = undoManager
    record(model, undoing: true, on: undoManager)
  }

  /// Registers the inverse of the last move: an undo after an apply or a redo, a redo after an
  /// undo.
  private static func record(
    _ model: StudioWorkspaceModel, undoing: Bool, on undoManager: UndoManager?
  ) {
    undoManager?.registerUndo(withTarget: model) { target in
      MainActor.assumeIsolated {
        guard !target.isRetired else { return }
        target.reveal()
        guard (try? undoing ? target.undo() : target.redo()) != nil else { return }
        record(target, undoing: !undoing, on: undoManager)
      }
    }
    undoManager?.setActionIsDiscardable(true)
  }
}
