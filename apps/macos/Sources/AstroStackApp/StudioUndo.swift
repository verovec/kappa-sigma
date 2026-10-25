internal import AppKit
package import Foundation

/// The Studio's moves on the window's undo manager (cards 0087, 0117, 0119): an Apply — from the
/// button or Edit › Apply Process — a pipeline run, a replay registers its undo, which registers
/// the redo, and so on; the history's Undo / Redo buttons take the same stack, so ⌘Z and the
/// buttons never drift.
///
/// A run is one move of all its steps, the head shown once, and puts the pipeline column back
/// with it (its breakpoint, the values a Continue wrote). A move names the history it moves (the
/// combined image or a layer's branch) and shows it first; it acts only if that head is still the
/// one it recorded, so ⌘Z never undoes another step than the one it names; it is refused, not
/// consumed, while a run, a replay or a host tool moves a history (`ProjectUndoManager`). The
/// actions are discardable (the history is on disk at once: a titled project is never marked
/// edited by them), removed when their workspace is replaced, and a move made from another
/// stage brings the Studio into view first.
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
        recordNew(model, steps: 1, in: .main, name: actionName, mark: nil, on: undoManager)
      }
      return
    }
    defer { done() }
    try? model.apply()
    guard model.steps.count > before else { return }
    // The step goes to the history shown (card 0119): its ⌘Z undoes it there.
    recordNew(model, steps: 1, in: model.selection, name: actionName, mark: nil, on: undoManager)
  }

  /// The steps a pipeline run (or a replay) added to the combined image after its first `count`:
  /// one ⌘Z takes them back and puts the column back at `mark`, its state before the run.
  ///
  /// A workspace retired while its run went on registers nothing: its moves were removed.
  package static func recordRun(
    _ model: StudioWorkspaceModel, from count: Int, mark: PipelineSidebarModel.Mark? = nil,
    on undoManager: UndoManager?
  ) {
    let added = model.studio.steps.count - count
    guard added > 0 else { return }
    recordNew(
      model, steps: added, in: .main, name: .app("Run Pipeline"), mark: mark, on: undoManager)
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
    // registered once the replay ended (in a group of its own, `register`).
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

  /// The history's Undo button: ⌘Z itself when the window's last action is a step back on the
  /// history shown, else one step back there, registered so ⌘Z redoes it — also when that move
  /// went stale (the head moved since), so the button never does nothing.
  package static func undo(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    // A replay, a run or a tool holds a history: the button waits, as ⌘Z does.
    guard !model.isMovingHistory else { return }
    if let undoManager, undoManager.canUndo,
      isOwn(undoManager.undoActionUserInfoValue(forKey: ownerKey), model, backward: true),
      moves(model, by: undoManager.undo)
    {
      return
    }
    outOfBand(model, backward: true, on: undoManager)
  }

  /// The history's Redo button: ⇧⌘Z itself when the window's last undo was a step back on the
  /// history shown, else one step forward there, registered so ⌘Z takes it back.
  package static func redo(_ model: StudioWorkspaceModel, undoManager: UndoManager?) {
    guard !model.isMovingHistory else { return }
    if let undoManager, undoManager.canRedo,
      isOwn(undoManager.redoActionUserInfoValue(forKey: ownerKey), model, backward: false),
      moves(model, by: undoManager.redo)
    {
      return
    }
    outOfBand(model, backward: false, on: undoManager)
  }

  /// Whether a move tagged `owner` must wait for a run, a replay or a host tool.
  ///
  /// Edit › Undo is greyed meanwhile, the move kept (`ProjectUndoManager`).
  static func isRefused(_ owner: Any?) -> Bool {
    (owner as? StudioMoveTarget)?.workspace?.isMovingHistory == true
  }

  /// The user-info key tagging a Studio move with its workspace, direction and history: how the
  /// buttons recognise their own moves, whatever the action's localised name.
  static let ownerKey = UndoManager.UserInfoKey(rawValue: "fr.astrostack.studio.move")

  /// What Edit › Undo says of a Studio step.
  static var actionName: LocalizedStringResource { .app("Studio Step") }

  /// Whether `tag` names a move of `model` in that direction on the history it shows.
  private static func isOwn(_ tag: Any?, _ model: StudioWorkspaceModel, backward: Bool) -> Bool {
    guard let target = tag as? StudioMoveTarget else { return false }
    return target.workspace === model && target.backward == backward
      && target.selection == model.selection
  }

  /// Whether `move` changed the head of the history shown.
  private static func moves(_ model: StudioWorkspaceModel, by move: () -> Void) -> Bool {
    let (selection, head) = (model.selection, model.steps.map(\.file))
    move()
    return model.selection == selection && model.steps.map(\.file) != head
  }

  /// One step moved by a button behind ⌘Z's back, its inverse registered on top.
  ///
  /// ⌘Z still follows the history: the earlier moves chain again once the inverse is made. A
  /// new step there breaks that chain (the redo it discards): `recordNew` then drops them all.
  private static func outOfBand(
    _ model: StudioWorkspaceModel, backward: Bool, on undoManager: UndoManager?
  ) {
    guard (try? backward ? model.undo() : model.redo()) != nil, let undoManager, !model.isRetired
    else { return }
    model.undoManager = undoManager
    model.movedOutOfBand.insert(model.selection)
    let inverse = StudioMove(
      steps: 1, backward: !backward, selection: model.selection, head: model.steps.last?.file,
      name: actionName, mark: nil)
    register(inverse, model, on: undoManager)
  }

  /// Registers the undo of `steps` new steps on the history of `selection`: its redo is gone,
  /// and with it every move forward registered there — and every move after a button's move.
  private static func recordNew(
    _ model: StudioWorkspaceModel, steps: Int, in selection: StudioSelection,
    name: LocalizedStringResource, mark: PipelineSidebarModel.Mark?, on undoManager: UndoManager?
  ) {
    guard let undoManager, !model.isRetired else { return }
    model.undoManager = undoManager
    let broken = model.movedOutOfBand.contains(selection)
    let dropped = model.moveTargets.filter {
      $0.selection == selection && (broken || !$0.backward)
    }
    if drop(dropped, on: undoManager) { model.movedOutOfBand.remove(selection) }
    let move = StudioMove(
      steps: steps, backward: true, selection: selection,
      head: model.studio.steps(of: selection).last?.file, name: name, mark: mark)
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

  /// Registers `move` in a group of its own, tagged with its workspace, direction and history.
  private static func register(
    _ move: StudioMove, _ model: StudioWorkspaceModel, on undoManager: UndoManager
  ) {
    let target = model.moveTarget(backward: move.backward, in: move.selection)
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

  /// Makes `move` on its history (shown first) if its head is still the one it recorded, puts
  /// the column back at its mark and registers the inverse, which puts the column back as it is.
  private static func perform(
    _ move: StudioMove, _ model: StudioWorkspaceModel, on undoManager: UndoManager
  ) {
    guard !model.isRetired, !model.isMovingHistory,
      model.studio.steps(of: move.selection).last?.file == move.head
    else { return }
    model.reveal()
    model.select(move.selection)
    // A replay or a run holds the combined image: never undo another history instead.
    guard model.selection == move.selection else { return }
    let now = move.mark.flatMap {
      model.pipeline?.mark(keeping: $0.recipes.keys, whole: $0.pipeline != nil)
    }
    let moved = Result {
      try move.backward ? model.undo(steps: move.steps) : model.redo(steps: move.steps)
    }
    guard case .success = moved else { return }
    if let mark = move.mark { model.pipeline?.restore(mark) }
    let inverse = StudioMove(
      steps: move.steps, backward: !move.backward, selection: move.selection,
      head: model.steps.last?.file, name: move.name, mark: now)
    register(inverse, model, on: undoManager)
  }
}
