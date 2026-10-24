package import Foundation

/// The project window's undo manager (card 0117): while a pipeline run or a host tool moves the
/// Studio's history, a Studio move on top of the stack is refused — Edit › Undo / Redo greyed,
/// the history's buttons too — never taken off the stack and dropped.
package final class ProjectUndoManager: UndoManager {
  override package var canUndo: Bool {
    super.canUndo && !refuses(undoActionUserInfoValue(forKey: StudioUndo.ownerKey))
  }

  override package var canRedo: Bool {
    super.canRedo && !refuses(redoActionUserInfoValue(forKey: StudioUndo.ownerKey))
  }

  override package func undo() {
    guard canUndo else { return }
    super.undo()
  }

  override package func redo() {
    guard canRedo else { return }
    super.redo()
  }

  /// Off the main thread (an AppKit query) nothing is refused: a Studio move only runs there.
  private func refuses(_ owner: Any?) -> Bool {
    guard owner != nil, Thread.isMainThread else { return false }
    return MainActor.assumeIsolated { StudioUndo.isRefused(owner) }
  }
}
