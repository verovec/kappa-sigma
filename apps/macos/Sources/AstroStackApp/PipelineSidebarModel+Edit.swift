internal import AppKit
package import Foundation
internal import ProcessKit

/// Card 0107: removing and moving steps not applied yet. An applied step is changed by undoing
/// back before it, never by rewriting the history (R2: the pixels made stay until the user undoes
/// them), so the history keeps following the pipeline by construction.
extension PipelineSidebarModel {
  /// Why step `index` cannot be removed or moved, `nil` when it can.
  package func editRefusal(of index: Int) -> LocalizedStringResource? {
    if index < workspace.studio.steps.count {
      return .app("Undo back before this step to change it")
    }
    if isRunning { return .app("Wait for the run to end") }
    // A host tool's Apply records its step where the pipeline stands when it ends.
    return workspace.toolTask == nil
      ? nil : .app("A tool is already running: wait for it, or stop it.")
  }

  /// Whether step `index` exists and can be removed or moved.
  package func canEdit(_ index: Int) -> Bool {
    pipeline.steps.indices.contains(index) && editRefusal(of: index) == nil
  }

  /// Removes step `index` when it can be; undoable on `undoManager`.
  ///
  /// The breakpoint follows its step, cleared when it is this one: the panel keeps its process,
  /// not applied.
  package func remove(at index: Int, undoManager: UndoManager? = nil) {
    guard canEdit(index) else { return }
    let step = pipeline.steps[index]
    let halted = stoppedAt == index
    pipeline = pipeline.removing(at: index)
    stoppedAt = stoppedAt.flatMap { current -> Int? in
      current == index ? nil : current > index ? current - 1 : current
    }
    register(on: undoManager) {
      $0.insert(step, at: index, halted: halted, undoManager: undoManager)
    }
  }

  /// Moves step `from` so it is step `to`, both not applied yet; undoable on `undoManager`.
  ///
  /// The breakpoint follows its step.
  package func move(from: Int, to: Int, undoManager: UndoManager? = nil) {
    guard from != to, canEdit(from), canEdit(to) else { return }
    pipeline = pipeline.moving(from: from, to: to)
    stoppedAt = stoppedAt.map { current -> Int in
      if current == from { return to }
      let shifted = current > from ? current - 1 : current
      return shifted >= to ? shifted + 1 : shifted
    }
    register(on: undoManager) { $0.move(from: to, to: from, undoManager: undoManager) }
  }

  /// Puts a removed `step` back as step `index` (its undo), the run halted before it again when
  /// it was (`halted`); only among the steps not applied yet.
  private func insert(
    _ step: PipelineStep, at index: Int, halted: Bool, undoManager: UndoManager?
  ) {
    guard index <= pipeline.steps.count, editRefusal(of: index) == nil else { return }
    pipeline.steps.insert(step, at: index)
    if halted {
      stoppedAt = index
    } else if let current = stoppedAt, current >= index {
      stoppedAt = current + 1
    }
    register(on: undoManager) { $0.remove(at: index, undoManager: undoManager) }
  }

  /// Registers `inverse` as the undo of an edit: the inverse edit itself, refused like any edit
  /// once its steps are applied, so a later toggle elsewhere never blocks it.
  private func register(
    on undoManager: UndoManager?, _ inverse: @escaping @MainActor (PipelineSidebarModel) -> Void
  ) {
    // On the workspace: replacing it drops these with its own moves (`retire`).
    undoManager?.registerUndo(withTarget: workspace) { [weak self] workspace in
      MainActor.assumeIsolated {
        guard let self, !workspace.isRetired else { return }
        workspace.reveal()
        inverse(self)
      }
    }
    undoManager?.setActionIsDiscardable(true)
  }
}
