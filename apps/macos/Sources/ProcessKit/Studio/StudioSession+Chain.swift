internal import ImageKit

// MARK: - The chain preview of a revised step (card 0158)

extension StudioSession {
  /// Applied step `k` with `params`, then the steps after it with their recorded values, in
  /// memory at full resolution: the pixels a revise (0157) writes, the history left untouched.
  ///
  /// Each step reads what Apply would give it: the statistics of its input, the layers the steps
  /// before it wrote — those of the chain from its own outputs — and its recorded mask (card
  /// 0160, k included). The chain stops before the first host-tool step (k included): that step
  /// runs at the revise. A crop, turn or flip k with a masked step after it is refused
  /// (`PipelineError.maskMoved`), as the revise refuses it.
  package func previewChain(from k: Int, params: ParamSet) throws -> ChainPreview {
    let steps = history.steps
    guard steps.indices.contains(k) else { throw HistoryError.noStep(k) }
    // A process the registry cannot render counts as a tool, as in the revise.
    let stop = steps.indices[k...].first { index in
      let recipe = Recipe(
        processID: steps[index].processID, params: index == k ? params : steps[index].params)
      return registry.type(id: recipe.processID).map(recipe.runsTool(as:)) ?? true
    }
    if let masked = movedMaskStep(k, params: params, until: stop ?? steps.count) {
      throw PipelineError.maskMoved(step: masked)
    }
    let input = try chainInput(k)
    var state = input.state
    for index in k..<(stop ?? steps.count) {
      let recipe = Recipe(
        processID: steps[index].processID, params: index == k ? params : steps[index].params)
      guard let type = registry.type(id: recipe.processID) else { break }
      // The recorded values as the replay reads them: a refused value stops it with its name.
      let values = try PipelineRunner.values(
        of: PipelineStep(recipe: recipe), schema: type.schema, at: index)
      let step = try runner.applied(
        type.init(params: values, device: device), input: state.image,
        stats: state.stats ?? LayerStats.measured(state.image), layers: state.layers,
        layerStats: state.layerStats, roles: state.roles, mask: input.masks[index])
      try state.advance(
        past: step, of: recipe.processID, moving: registry.movingIDs, stack: bundle.layerStats,
        device: device)
    }
    return ChainPreview(image: state.image, stoppedBefore: stop)
  }

  /// The first masked step after `k` and before `end` when step `k` moves the pixels under its
  /// recorded values or under `params`: its recorded mask would land on other pixels (card
  /// 0160). The one rule of the revise's refusal and of the chain preview's.
  package func movedMaskStep(_ k: Int, params: ParamSet, until end: Int) -> Int? {
    let steps = history.steps
    guard steps.indices.contains(k) else { return nil }
    let step = steps[k]
    guard
      registry.movesPixels(step.processID, params: params)
        || registry.movesPixels(step.processID, params: step.params)
    else { return nil }
    return steps.indices[(k + 1)..<max(k + 1, min(end, steps.count))]
      .first { steps[$0].mask != nil }
  }

  /// The files of the steps when the chain input was cached, or `nil` when none is kept.
  package var chainInputFiles: [String]? { chainInput?.files }

  /// Drops the cached input of the chain preview: the edit is over.
  package func endChainPreview() {
    chainInput = nil
  }

  /// What step `k` reads and the recorded masks of the steps from it, read from the history
  /// once per edit (the same `k` over the same step files).
  func chainInput(_ k: Int) throws -> (state: ChainState, masks: [Int: AstroImage]) {
    let steps = history.steps
    let files = steps.map(\.file)
    if let chainInput, chainInput.k == k, chainInput.files == files {
      return (chainInput.state, chainInput.masks)
    }
    let before = Array(steps.prefix(k))
    let moving = registry.movingIDs
    let image = try history.image(file: before.last?.file)
    let context = try history.contextAndMoves(
      over: bundleLayers, stats: bundle.layerStats, device: device, moving: moving, before: k)
    let state = ChainState(
      image: image, stats: k == 0 ? bundle.stats : LayerStats.measured(image),
      layers: context.layers, layerStats: context.stats, onlyMoved: context.onlyMoved,
      roles: Set(before.flatMap { $0.outputs.keys }))
    var masks: [Int: AstroImage] = [:]
    for index in steps.indices[k...] where steps[index].mask != nil {
      masks[index] = try history.mask(ofStep: index)
    }
    chainInput = (k, files, state, masks)
    return (state, masks)
  }
}
