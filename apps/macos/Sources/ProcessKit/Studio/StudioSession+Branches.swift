package import ImageKit

// MARK: - Branches (card 0118)

extension StudioSession {
  /// The image `processID` with `params` makes of the head of branch `layerID` (at `scale`).
  ///
  /// The branch's preview and Apply both come from here; the head alone is read (no layer).
  package func renderBranch(
    _ layerID: String, _ processID: String, params: ParamSet, scale: Double = 1,
    purpose: RenderContext.Purpose = .apply
  ) throws -> AstroImage {
    let (type, layer) = try branchable(layerID, processID, params: params)
    let head = branches.branch(layerID)?.head
    // The stack's statistics until the branch has a step, then its head's with the stack's fit:
    // what the main history reads for the same head (`BranchSet.overlay`).
    let recorded = stackBundle.layerStats[layerID]
    let stats =
      head.map { LayerStats.measured($0).keepingFit(of: recorded) } ?? recorded
      ?? LayerStats.measured(layer)
    return try runner.image(
      type.init(params: params, device: device), input: head ?? layer, stats: stats, scale: scale,
      purpose: purpose)
  }

  /// Applies `processID` with `params` to branch `layerID` at full resolution: its head moves,
  /// and the main history reads it from now on (its steps that read the old one go stale).
  package func applyBranch(_ layerID: String, _ processID: String, params: ParamSet) throws {
    let result = try renderBranch(layerID, processID, params: params)
    let layer = try stackLayer(layerID)
    try branches.branch(layerID, layer: layer).history.apply(
      processID: processID, params: params, result: result)
    try branchMoved(layerID)
  }

  /// Back one step on branch `layerID`.
  package func undoBranch(_ layerID: String) throws {
    guard let branch = branches.branch(layerID) else { throw HistoryError.nothingToUndo }
    try branch.history.undo()
    try branchMoved(layerID)
  }

  /// Forward one undone step on branch `layerID`.
  package func redoBranch(_ layerID: String) throws {
    guard let branch = branches.branch(layerID) else { throw HistoryError.nothingToRedo }
    try branch.history.redo()
    try branchMoved(layerID)
  }

  /// The first main step that read a branch head which has moved since, or `nil`.
  ///
  /// From it on, the main history is not what its steps would make now. Shown, never
  /// re-applied by itself (R2): Replay re-runs them with their recorded values.
  package var staleFrom: Int? {
    history.steps.indices.first { index in
      let step = history.steps[index]
      return step.branchHeads != headsRead(step.processID, params: step.params, index: index)
    }
  }

  /// Why branch `layerID` refuses `processID` with `params`, or the process and the layer.
  func branchable(_ layerID: String, _ processID: String, params: ParamSet) throws
    -> (any ImageProcess.Type, AstroImage)
  {
    guard let type = registry.type(id: processID) else {
      throw StudioError.unknownProcess(processID)
    }
    let layer = try stackLayer(layerID)
    if let reason = Self.refusal(of: type, planes: layer.planes.count) {
      throw StudioError.notBranchable(processID: processID, reason: reason)
    }
    if type.runsTool(params) { throw StudioError.needsTool(processID) }
    return (type, layer)
  }

  /// Why a branch over a layer of `planes` planes refuses `type`, or `nil`.
  static func refusal(of type: any ImageProcess.Type, planes: Int) -> StudioError.BranchRefusal? {
    if type is any GeometricProcess.Type { return .movesPixels }
    switch type.branchable {
    case .never: return .notPerLayer
    case .colourLayers where planes != 3: return .needsColour
    case .anyLayer, .colourLayers: return nil
    }
  }

  /// The heads of the branches a main step of `processID` with `params` at `index` reads: the
  /// layers it declares (`ImageProcess.layersRead`), and the base layer for the first step (the
  /// main history starts from it).
  func headsRead(_ processID: String, params: ParamSet, index: Int) -> [String: String] {
    let ids = Set(stackBundle.layers.keys)
    var read = registry.type(id: processID)?.layersRead(params, layerIDs: ids) ?? []
    if index == 0, let base = Self.baseLayerID(ids) { read.insert(base) }
    return branches.heads.filter { read.contains($0.key) }
  }

  private func stackLayer(_ layerID: String) throws -> AstroImage {
    guard let layer = stackBundle.layers[layerID] else {
      throw ProcessError.missingLayer(layerID)
    }
    return layer
  }

  /// Branch `layerID` moved: the main history reads its new head (or the stacked layer), and
  /// starts from it when it is the base layer.
  private func branchMoved(_ layerID: String) throws {
    let baseID = Self.baseLayerID(stackBundle.layers.keys)
    let layer = try stackLayer(layerID)
    let head = branches.branch(layerID)?.head
    // Only the layer that moved is measured and uploaded again.
    BranchSet.overlay(head, of: layerID, onto: &bundle, stack: stackBundle, baseID: baseID)
    bundleLayers[layerID] = try GPUImage(device: device, image: head ?? layer)
    overlay = nil
    if layerID == baseID { history.rebase(onto: head ?? layer) }
  }
}
