internal import AppKit
package import Foundation

/// The Studio's moves on the window's undo manager (card 0087): an Apply — from the button or
/// Edit › Apply Process — registers its undo, which registers the redo, and so on.
///
/// Each registered move acts only if the history's head is still the step it recorded (its
/// output file; the history buttons move it directly), so ⌘Z never undoes another step than the
/// one it names. The actions
/// are discardable (the history is on disk at once: a titled project is never marked edited by
/// them), removed when their workspace is replaced, and a move made from another stage brings
/// the Studio into view first.
package enum StudioUndo {
  /// Applies the panel of `model` and registers the move with `undoManager` when a step was
  /// added; `done` runs once it is (a host tool's Apply ends later).
  package static func apply(
    _ model: StudioWorkspaceModel, undoManager: UndoManager?, then done: @escaping () -> Void = {}
  ) {
    // Read before the commit below, whose value change ends the suspension: a press that reads
    // « Preview » previews, whatever was typed.
    let previews = model.isPreviewSuspended
    // A value typed and not confirmed is committed first: Apply never records an older one.
    NSApp?.keyWindow?.makeFirstResponder(nil)
    if previews {
      model.resumePreview()
      done()
      return
    }
    let before = model.studio.steps.count
    // A host tool (plate solving) runs in the background; its step is registered when recorded.
    if let panel = model.panel, panel.type.runsTool(panel.params) {
      model.startTool { [weak model, weak undoManager] recorded in
        defer { done() }
        // Only the tool's own step: another Apply made meanwhile registered its own undo.
        guard recorded, let model else { return }
        model.undoManager = undoManager
        record(model, undoing: true, head: model.studio.steps.last?.file, on: undoManager)
      }
      return
    }
    defer { done() }
    try? model.apply()
    guard model.studio.steps.count > before else { return }
    model.undoManager = undoManager
    record(model, undoing: true, head: model.studio.steps.last?.file, on: undoManager)
  }

  /// Registers the inverse of the last move, valid while the history's head is the step whose
  /// output is `head` (`nil`: the original): an undo after an apply or a redo, a redo after an
  /// undo.
  private static func record(
    _ model: StudioWorkspaceModel, undoing: Bool, head: String?, on undoManager: UndoManager?
  ) {
    undoManager?.registerUndo(withTarget: model) { [weak undoManager] target in
      MainActor.assumeIsolated {
        guard !target.isRetired, target.studio.steps.last?.file == head else { return }
        target.reveal()
        guard (try? undoing ? target.undo() : target.redo()) != nil else { return }
        record(target, undoing: !undoing, head: target.studio.steps.last?.file, on: undoManager)
      }
    }
    undoManager?.setActionIsDiscardable(true)
  }
}
