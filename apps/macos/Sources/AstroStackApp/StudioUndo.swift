internal import AppKit
package import Foundation

/// The Studio's moves on the window's undo manager (cards 0087, 0117): an Apply — from the
/// button or Edit › Apply Process — a pipeline run or a replay registers its undo, which
/// registers the redo, and so on; the history's Undo / Redo buttons take the same stack, so ⌘Z
/// and the buttons never drift.
///
/// A run is one move of all its steps, the head shown once, and puts the pipeline column back
/// with it (its breakpoint, the values a Continue wrote). Each move acts only if the history's
/// head is still the one it recorded, so ⌘Z never undoes another step than the one it names; a
/// move is refused, not consumed, while a run or a host tool moves the history
/// (`ProjectUndoManager`). The actions are discardable (the history is on disk at once: a
/// titled project is never marked edited by them), removed when their workspace is replaced,
/// and a move made from another stage brings the Studio into view first.
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
        recordNew(model, steps: 1, name: actionName, mark: nil, on: undoManager)
      }
      return
    }
    defer { done() }
    try? model.apply()
    guard model.studio.steps.count > before else { return }
    recordNew(model, steps: 1, name: actionName, mark: nil, on: undoManager)
  }

  /// The steps a pipeline run added after the history's first `count`: one ⌘Z takes them back
  /// and puts the column back at `mark`, its state before the run.
  ///
  /// A workspace retired while its run went on registers nothing: its moves were removed.
  package static func recordRun(
    _ model: StudioWorkspaceModel, from count: Int, mark: PipelineSidebarModel.Mark? = nil,
    on undoManager: UndoManager?
  ) {
    let added = model.studio.steps.count - count
    guard added > 0 else { return }
    recordNew(model, steps: added, name: .app("Run Pipeline"), mark: mark, on: undoManager)
  }

  /// Re-applies the stale main steps (card 0118) and registers them as one move (in a group
  /// of its own, `register`).
  ///
  /// One ⌘Z takes the whole replay (`StudioModel.replayMain`) back; a failure is shown in the
  /// panel.
  package static func replayMain(_ model: StudioWorkspaceModel, on undoManager: UndoManager?)
    async throws
  {
    let studio = model.studio
    guard let start = studio.staleFrom else { return }
    // Even a replay that stops on a failure keeps the steps it applied: they are undoable too.
    defer { recordRun(model, from: start, on: undoManager) }
    do {
      try await studio.replayMain()
    } catch {
      model.failure = UserFacingError(error).message
      try? model.headChanged()
      throw error
    }
    try model.headChanged()
  }

  /// The history's Undo button: ⌘Z itself when the window's last action is this Studio's step
  /// back, else one step back on the history, registered so ⌘Z redoes it — also when that move
  /// went stale (the head moved since), so the button never does nothing.
  package static func undo(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    guard !model.isMovingHistory else { return }
    if let undoManager, undoManager.canUndo,
      undoManager.undoActionUserInfoValue(forKey: ownerKey) as AnyObject? === model.backMoves,
      moves(model, by: undoManager.undo)
    {
      return
    }
    outOfBand(model, backward: true, on: undoManager)
  }

  /// The history's Redo button: ⇧⌘Z itself when the window's last undo was this Studio's step
  /// back, else one step forward on the history, registered so ⌘Z takes it back.
  package static func redo(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    guard !model.isMovingHistory else { return }
    if let undoManager, undoManager.canRedo,
      undoManager.redoActionUserInfoValue(forKey: ownerKey) as AnyObject? === model.forwardMoves,
      moves(model, by: undoManager.redo)
    {
      return
    }
    outOfBand(model, backward: false, on: undoManager)
  }

  /// Whether a move tagged `owner` must wait for a run or a host tool moving its history.
  ///
  /// Edit › Undo is greyed meanwhile, the move kept (`ProjectUndoManager`).
  static func isRefused(_ owner: Any?) -> Bool {
    (owner as? StudioMoveTarget)?.workspace?.isMovingHistory == true
  }

  /// The user-info key tagging a Studio move with its workspace and direction: how the buttons
  /// recognise their own moves, whatever the action's localised name.
  static let ownerKey = UndoManager.UserInfoKey(rawValue: "fr.astrostack.studio.move")

  /// What Edit › Undo says of a Studio step.
  static var actionName: LocalizedStringResource { .app("Studio Step") }

  /// Whether `move` changed the history's head.
  private static func moves(_ model: StudioWorkspaceModel, by move: () -> Void) -> Bool {
    let head = model.studio.steps.map(\.file)
    move()
    return model.studio.steps.map(\.file) != head
  }

  /// One step moved by a button behind ⌘Z's back, its inverse registered on top.
  ///
  /// ⌘Z still follows the history: the earlier moves chain again once the inverse is made. A
  /// new step breaks that chain (the redo it discards): `recordNew` then drops them all.
  private static func outOfBand(
    _ model: StudioWorkspaceModel, backward: Bool, on undoManager: UndoManager?
  ) {
    guard (try? backward ? model.undo() : model.redo()) != nil, let undoManager, !model.isRetired
    else { return }
    model.undoManager = undoManager
    model.movedOutOfBand = true
    let inverse = StudioMove(
      steps: 1, backward: !backward, head: model.studio.steps.last?.file, name: actionName,
      mark: nil)
    register(inverse, model, on: undoManager)
  }

  /// Registers the undo of `steps` new steps: the history's redo is gone, and with it every move
  /// forward registered so far — and every move after a button's move (`outOfBand`).
  private static func recordNew(
    _ model: StudioWorkspaceModel, steps: Int, name: LocalizedStringResource,
    mark: PipelineSidebarModel.Mark?, on undoManager: UndoManager?
  ) {
    guard let undoManager, !model.isRetired else { return }
    model.undoManager = undoManager
    let dropped =
      model.movedOutOfBand ? [model.backMoves, model.forwardMoves] : [model.forwardMoves]
    if drop(dropped, on: undoManager) { model.movedOutOfBand = false }
    let move = StudioMove(
      steps: steps, backward: true, head: model.studio.steps.last?.file, name: name, mark: mark)
    register(move, model, on: undoManager)
  }

  /// Drops the moves registered with `targets`, between undo groups only.
  ///
  /// Inside an open group AppKit keeps the groups it empties, and ⌘Z would stay stuck on them,
  /// doing nothing. A move left in place (registered within another action's group) is refused
  /// by its head check.
  @discardableResult
  private static func drop(_ targets: [StudioMoveTarget], on undoManager: UndoManager) -> Bool {
    guard undoManager.groupingLevel == 0 else { return false }
    for target in targets { undoManager.removeAllActions(withTarget: target) }
    return true
  }

  /// Registers `move` in a group of its own, tagged with its workspace and direction.
  private static func register(
    _ move: StudioMove, _ model: StudioWorkspaceModel, on undoManager: UndoManager
  ) {
    let target = move.backward ? model.backMoves : model.forwardMoves
    undoManager.beginUndoGrouping()
    defer { undoManager.endUndoGrouping() }
    undoManager.registerUndo(withTarget: target) { [weak undoManager] target in
      MainActor.assumeIsolated {
        guard let model = target.workspace, let undoManager else { return }
        perform(move, model, on: undoManager)
      }
    }
    undoManager.setActionIsDiscardable(true)
    undoManager.setActionName(String(localized: move.name))
    undoManager.setActionUserInfoValue(target, forKey: ownerKey)
  }

  /// Makes `move` if the head is still the one it recorded, puts the column back at its mark and
  /// registers the inverse, which puts the column back as it is now.
  private static func perform(
    _ move: StudioMove, _ model: StudioWorkspaceModel, on undoManager: UndoManager
  ) {
    guard !model.isRetired, model.studio.steps.last?.file == move.head else { return }
    model.reveal()
    let now = move.mark.flatMap {
      model.pipeline?.mark(keeping: $0.recipes.keys, whole: $0.pipeline != nil)
    }
    let moved = Result {
      try move.backward ? model.undo(steps: move.steps) : model.redo(steps: move.steps)
    }
    guard case .success = moved else { return }
    if let mark = move.mark { model.pipeline?.restore(mark) }
    let inverse = StudioMove(
      steps: move.steps, backward: !move.backward, head: model.studio.steps.last?.file,
      name: move.name, mark: now)
    register(inverse, model, on: undoManager)
  }
}
