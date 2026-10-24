package import ProcessKit

// MARK: - Branches (card 0118)

extension StudioModel {
  /// Applies `processID` with `params` to the branch of bundle layer `layerID`: the main history
  /// reads its new head, and the main steps that read the old one go stale (`staleFrom`).
  package func applyBranch(_ layerID: String, _ processID: String, params: ParamSet) throws {
    defer { mirrorBranch(layerID) }
    try session.applyBranch(layerID, processID, params: params)
  }

  /// Back one step on the branch of `layerID`.
  package func undoBranch(_ layerID: String) throws {
    defer { mirrorBranch(layerID) }
    try session.undoBranch(layerID)
  }

  /// Forward one undone step on the branch of `layerID`.
  package func redoBranch(_ layerID: String) throws {
    defer { mirrorBranch(layerID) }
    try session.redoBranch(layerID)
  }

  /// Re-applies the main steps from `staleFrom` on with the values they recorded.
  ///
  /// Over the branch heads as they are now, only when asked (R2), through the pipeline runner
  /// like a replay (card 0088: a recipe has no mask, so a masked step replays unmasked). A
  /// host-tool step refuses the replay before anything moves (`PipelineError.toolMissing`).
  /// Returns the number of steps kept before the first one re-applied, or `nil` when nothing
  /// was stale.
  @discardableResult
  package func replayMain() async throws -> Int? {
    guard let start = staleFrom else { return nil }
    let recipes = steps.map {
      PipelineStep(recipe: Recipe(processID: $0.processID, params: $0.params))
    }
    let session = session
    // Checked before anything is undone: a step the runner cannot run would leave the head
    // rolled back with the stale steps dropped.
    for step in steps[start...] {
      let type = session.registry.type(id: step.processID)
      if type?.runsTool(step.params) ?? true { throw PipelineError.toolMissing(step.processID) }
    }
    let runner = try PipelineRunner(registry: session.registry, device: session.device)
    try await moving { history in
      while history.steps.count > start { try history.undo() }
      _ = try await runner.run(
        Pipeline(name: "replay", steps: recipes), on: history, bundle: session.bundle,
        from: start)
    }
    return start
  }

  /// Brings the rows of the layer's own project image (`images` row of role `layerID`, added
  /// with the stack) in line with its branch, and the main history's staleness with its head.
  private func mirrorBranch(_ layerID: String) {
    defer {
      refreshBranches()
      refresh()
    }
    guard let branch = session.branches.branch(layerID) else { return }
    cleanUp(branch.history)
    do {
      let images = try store.images(stackID: stackID)
      let imageID =
        try images.first { $0.role == layerID }?.id
        ?? store.addImage(stackID: stackID, role: layerID).id
      mirror(branch.history, on: imageID)
    } catch {
      Self.logger.error("branch mirror: \(String(describing: error), privacy: .public)")
    }
  }
}
