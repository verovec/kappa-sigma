package import ImageKit
package import ProcessKit

// MARK: - The history a selection names (card 0119)

extension StudioModel {
  /// The applied steps of the history of `selection`.
  package func steps(of selection: StudioSelection) -> [History.Step] {
    guard let id = selection.layerID else { return steps }
    return branchSteps[id] ?? []
  }

  /// The head of `selection`: the working image, or a branch's head (the layer as stacked while
  /// it has no step).
  package func head(of selection: StudioSelection) -> AstroImage {
    guard let id = selection.layerID else { return head }
    return session.branches.branch(id)?.head ?? session.stackBundle.layers[id] ?? head
  }

  /// What `processID` with `params` makes of the head of `selection` (the live preview); a branch
  /// takes no mask (its process reads the layer alone).
  package func preview(
    _ processID: String, params: ParamSet, on selection: StudioSelection, mask: AstroImage? = nil
  ) throws -> AstroImage {
    guard let id = selection.layerID else {
      return try preview(processID, params: params, mask: mask)
    }
    return try session.renderBranch(id, processID, params: params, purpose: .preview)
  }

  /// Applies `processID` with `params` to the history of `selection`.
  package func apply(
    _ processID: String, params: ParamSet, on selection: StudioSelection, mask: AstroImage? = nil
  ) throws {
    guard let id = selection.layerID else {
      return try apply(processID, params: params, mask: mask)
    }
    try applyBranch(id, processID, params: params)
  }

  /// Back one step on the history of `selection`.
  package func undo(on selection: StudioSelection) throws {
    guard let id = selection.layerID else { return try undo() }
    try undoBranch(id)
  }

  /// Forward one undone step on the history of `selection`.
  package func redo(on selection: StudioSelection) throws {
    guard let id = selection.layerID else { return try redo() }
    try redoBranch(id)
  }

  /// The output of applied step `index` of the history of `selection`, read back from disk.
  package func output(ofStep index: Int, on selection: StudioSelection) throws -> AstroImage {
    guard let id = selection.layerID else { return try session.history.output(ofStep: index) }
    guard let branch = session.branches.branch(id) else { throw HistoryError.noStep(index) }
    return try branch.history.output(ofStep: index)
  }

  /// Whether the history of `selection` has a step to undo.
  package func canUndo(on selection: StudioSelection) -> Bool {
    !steps(of: selection).isEmpty
  }

  /// Whether the history of `selection` has an undone step to redo.
  package func canRedo(on selection: StudioSelection) -> Bool {
    guard let id = selection.layerID else { return canRedo }
    return session.branches.branch(id)?.history.canRedo ?? false
  }
}
