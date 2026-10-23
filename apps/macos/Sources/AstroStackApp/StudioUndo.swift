internal import AppKit
package import Foundation

/// The Studio's moves on the window's undo manager (card 0087): an Apply — from the button or
/// Edit › Apply Process — or a pipeline run registers its undo, which registers the redo, and so
/// on.
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
    // A value typed and not confirmed is committed first: Apply never records an older one.
    NSApp?.keyWindow?.makeFirstResponder(nil)
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

  /// The steps a pipeline run added after the history's first `count`: one ⌘Z takes them all
  /// back, one ⇧⌘Z runs them again.
  package static func recordRun(
    _ model: StudioWorkspaceModel, from count: Int, on undoManager: UndoManager?
  ) {
    let added = model.studio.steps.count - count
    guard let undoManager, added > 0 else { return }
    model.undoManager = undoManager
    let run = Run(count: count, added: added)
    record(model, run: run, undoing: true, head: model.studio.steps.last?.file, on: undoManager)
  }

  /// A run's steps: the history's first `count` stay, `added` follow.
  private struct Run {
    let count: Int
    let added: Int
  }

  /// Registers the inverse of a run's move, valid while the head is `head`: one action for all
  /// its steps, so a ⌘Z never takes part of a run and the head is shown once.
  private static func record(
    _ model: StudioWorkspaceModel, run: Run, undoing: Bool, head: String?,
    on undoManager: UndoManager
  ) {
    undoManager.registerUndo(withTarget: model) { [weak undoManager] target in
      MainActor.assumeIsolated {
        guard let undoManager, movable(target, head: head) else { return }
        target.reveal()
        do {
          if undoing { try target.undo(to: run.count) } else { try target.redo(steps: run.added) }
        } catch { return }
        let now = target.studio.steps.last?.file
        record(target, run: run, undoing: !undoing, head: now, on: undoManager)
      }
    }
    undoManager.setActionIsDiscardable(true)
    undoManager.setActionName(String(localized: .app("Run Pipeline")))
  }

  /// Whether a registered move may act on `model`: not replaced, no run moving the history, and
  /// the head still the step it recorded.
  private static func movable(_ model: StudioWorkspaceModel, head: String?) -> Bool {
    !model.isRetired && model.pipeline?.isRunning != true && model.studio.steps.last?.file == head
  }

  /// Registers the inverse of the last move, valid while the history's head is the step whose
  /// output is `head` (`nil`: the original): an undo after an apply or a redo, a redo after an
  /// undo.
  private static func record(
    _ model: StudioWorkspaceModel, undoing: Bool, head: String?, on undoManager: UndoManager?
  ) {
    undoManager?.registerUndo(withTarget: model) { [weak undoManager] target in
      MainActor.assumeIsolated {
        guard movable(target, head: head) else { return }
        target.reveal()
        guard (try? undoing ? target.undo() : target.redo()) != nil else { return }
        record(target, undoing: !undoing, head: target.studio.steps.last?.file, on: undoManager)
      }
    }
    undoManager?.setActionIsDiscardable(true)
  }
}
