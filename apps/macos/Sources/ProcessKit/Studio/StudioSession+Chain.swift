internal import ImageKit

// MARK: - The chain preview of a revised step (card 0158)

extension StudioSession {
  /// Applied step `k` with `params`, then the steps after it with their recorded values, in
  /// memory at full resolution: the pixels a revise (0157) writes, the history left untouched.
  ///
  /// Each step reads what Apply would give it: the statistics of its input, the layers the steps
  /// before it wrote — those of the chain from its own outputs. The chain stops before the first
  /// host-tool step (k included): that step runs at the revise. A recipe has no mask: a masked
  /// step renders unmasked, as the revise replays it (until 0160).
  package func previewChain(from k: Int, params: ParamSet) throws -> ChainPreview {
    let steps = history.steps
    guard steps.indices.contains(k) else { throw HistoryError.noStep(k) }
    var state = try chainInput(k)
    for index in k..<steps.count {
      let recipe = Recipe(
        processID: steps[index].processID, params: index == k ? params : steps[index].params)
      // A process the registry cannot render counts as a tool, as in the revise.
      guard let type = registry.type(id: recipe.processID), !recipe.runsTool(as: type) else {
        return ChainPreview(image: state.image, stoppedBefore: index)
      }
      // The recorded values as the replay reads them: a refused value stops it with its name.
      let values = try PipelineRunner.values(
        of: PipelineStep(recipe: recipe), schema: type.schema, at: index)
      let step = try runner.applied(
        type.init(params: values, device: device), input: state.image,
        stats: state.stats ?? LayerStats.measured(state.image), layers: state.layers,
        layerStats: state.layerStats, roles: state.roles)
      try state.advance(
        past: step, of: recipe.processID, moving: registry.movingIDs, stack: bundle.layerStats,
        device: device)
    }
    return ChainPreview(image: state.image, stoppedBefore: nil)
  }

  /// The files of the steps before the cached chain input, or `nil` when none is kept.
  package var chainInputFiles: [String]? { chainInput?.files }

  /// Drops the cached input of the chain preview: the edit is over.
  package func endChainPreview() {
    chainInput = nil
  }

  /// What step `k` reads, read from the history once per set of files before it.
  func chainInput(_ k: Int) throws -> ChainState {
    let before = Array(history.steps.prefix(k))
    let files = before.map(\.file)
    if let chainInput, chainInput.files == files { return chainInput.state }
    let moving = registry.movingIDs
    let image = try history.image(file: before.last?.file)
    let (layers, layerStats) = try history.context(
      over: bundleLayers, stats: bundle.layerStats, device: device, moving: moving, before: k)
    let state = ChainState(
      image: image, stats: k == 0 ? bundle.stats : LayerStats.measured(image), layers: layers,
      layerStats: layerStats, onlyMoved: History.onlyMoved(before, moving: moving),
      roles: Set(before.flatMap { $0.outputs.keys }))
    chainInput = (files, state)
    return state
  }
}
