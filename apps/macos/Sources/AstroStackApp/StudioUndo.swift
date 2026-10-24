internal import AppKit
package import Foundation

/// The Studio's moves on the window's undo manager (card 0087): an Apply — from the button or
/// Edit › Apply Process — or a pipeline run registers its undo, which registers the redo, and so
/// on; the history's Undo / Redo buttons take the same stack, so ⌘Z and the buttons never drift.
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
    let before = model.steps.count
    // A host tool (plate solving) runs in the background; its step is registered when recorded.
    if let panel = model.panel, panel.type.runsTool(panel.params) {
      model.startTool { [weak model, weak undoManager] recorded in
        defer { done() }
        // Only the tool's own step: another Apply made meanwhile registered its own undo.
        guard recorded, let model else { return }
        model.undoManager = undoManager
        let head = model.studio.steps.last?.file
        record(model, undoing: true, in: .main, head: head, on: undoManager)
      }
      return
    }
    defer { done() }
    try? model.apply()
    // The step goes to the history shown (card 0119): its ⌘Z undoes it there.
    let selection = model.selection
    guard model.steps.count > before else { return }
    model.undoManager = undoManager
    record(model, undoing: true, in: selection, head: model.steps.last?.file, on: undoManager)
  }

  /// The steps a pipeline run added after the history's first `count`: one ⌘Z takes them back.
  ///
  /// A workspace retired while its run went on registers nothing: its moves were removed.
  package static func recordRun(
    _ model: StudioWorkspaceModel, from count: Int, on undoManager: UndoManager?
  ) {
    let steps = model.studio.steps
    guard let undoManager, !model.isRetired, steps.count > count else { return }
    model.undoManager = undoManager
    // Oldest first: the group undoes the last step first, which leaves the head on the one before.
    for step in steps[count...] {
      record(model, undoing: true, in: .main, head: step.file, on: undoManager)
    }
  }

  /// Re-applies the stale main steps (card 0118) and registers them as one move.
  ///
  /// One ⌘Z takes the whole replay (`StudioModel.replayMain`) back; a failure is shown in the
  /// panel.
  package static func replayMain(_ model: StudioWorkspaceModel, on undoManager: UndoManager?)
    async throws
  {
    let studio = model.studio
    guard !model.isMovingMain, model.toolTask == nil, let start = studio.staleFrom else { return }
    model.isReplaying = true
    defer { model.isReplaying = false }
    // Even a replay that stops on a failure keeps the steps it applied: they are undoable too,
    // as one group opened and closed once the replay ended — never across its await, where an
    // undo would find a group left open.
    defer {
      undoManager?.beginUndoGrouping()
      recordRun(model, from: start, on: undoManager)
      undoManager?.endUndoGrouping()
    }
    do {
      try await studio.replayMain()
    } catch {
      model.failure = UserFacingError(error).message
      try? model.headChanged()
      throw error
    }
    try model.headChanged()
  }

  /// The history's Undo button: ⌘Z itself when the window's last action is a Studio move, else
  /// one step back on the history — also when that move went stale (the head moved since), so
  /// the button never does nothing.
  package static func undo(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    // A replay or a run holds the combined image: the button waits, as ⌘Z does.
    guard !model.isMovingMain else { return }
    if let undoManager, undoManager.canUndo, undoManager.undoActionName == actionName,
      model.undoSelections.last == model.selection, moves(model, by: undoManager.undo)
    {
      return
    }
    try? model.undo()
  }

  /// The history's Redo button: ⇧⌘Z itself when the window's last undo was a Studio move, else
  /// one step forward on the history.
  package static func redo(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    guard !model.isMovingMain else { return }
    if let undoManager, undoManager.canRedo, undoManager.redoActionName == actionName,
      model.redoSelections.last == model.selection, moves(model, by: undoManager.redo)
    {
      return
    }
    try? model.redo()
  }

  /// Whether `move` changed the head of the history shown.
  private static func moves(_ model: StudioWorkspaceModel, by move: () -> Void) -> Bool {
    let (selection, head) = (model.selection, model.steps.map(\.file))
    move()
    return model.selection == selection && model.steps.map(\.file) != head
  }

  /// What Edit › Undo says of a Studio move, and how the history's buttons recognise one.
  static var actionName: String { String(localized: .app("Studio Step")) }

  /// Registers the inverse of the last move on the history of `selection`.
  ///
  /// Valid while that head is the step whose output is `head` (`nil`: the original): an undo
  /// after an apply or a redo, a redo after an undo. It shows that history first (card 0119).
  private static func record(
    _ model: StudioWorkspaceModel, undoing: Bool, in selection: StudioSelection, head: String?,
    on undoManager: UndoManager?
  ) {
    guard let undoManager else { return }
    // Where the entry lands, as the undo manager decides: the redo stack while undoing, else the
    // undo stack — a new move (neither undoing nor redoing) empties the redo stack.
    if undoManager.isUndoing {
      model.redoSelections.append(selection)
    } else {
      model.undoSelections.append(selection)
      if !undoManager.isRedoing { model.redoSelections.removeAll() }
    }
    undoManager.registerUndo(withTarget: model) { [weak undoManager] target in
      MainActor.assumeIsolated {
        // The entry leaves its stack whatever it does next.
        if undoManager?.isRedoing == true {
          _ = target.redoSelections.popLast()
        } else {
          _ = target.undoSelections.popLast()
        }
        // A replay or a run rewrites the combined image: nothing moves, no inverse is recorded.
        guard !target.isRetired, !target.isMovingMain,
          target.studio.steps(of: selection).last?.file == head
        else {
          return
        }
        target.reveal()
        target.select(selection)
        // A replay or a run holds the combined image: never undo another history instead.
        guard target.selection == selection else { return }
        guard (try? undoing ? target.undo() : target.redo()) != nil else { return }
        let moved = target.studio.steps(of: selection).last?.file
        record(target, undoing: !undoing, in: selection, head: moved, on: undoManager)
      }
    }
    undoManager.setActionIsDiscardable(true)
    undoManager.setActionName(actionName)
  }
}
