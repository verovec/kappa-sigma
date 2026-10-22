package import Foundation

/// The Studio's moves on the window's undo manager (card 0087): an Apply — from the button or
/// Edit › Apply Process — registers its undo, which registers the redo, and so on.
package enum StudioUndo {
  /// Applies the panel of `model` and registers the move with `undoManager`.
  package static func apply(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    guard (try? model.apply()) != nil else { return }
    record(model, undoing: true, on: undoManager)
  }

  /// Registers the inverse of the last move: an undo after an apply or a redo, a redo after an
  /// undo.
  private static func record(
    _ model: StudioWorkspaceModel, undoing: Bool, on undoManager: UndoManager?
  ) {
    undoManager?.registerUndo(withTarget: model) { target in
      MainActor.assumeIsolated {
        guard (try? undoing ? target.undo() : target.redo()) != nil else { return }
        record(target, undoing: !undoing, on: undoManager)
      }
    }
  }
}
