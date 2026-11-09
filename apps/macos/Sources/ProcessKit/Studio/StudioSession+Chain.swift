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
  ///
  /// The caller's task's work (card 0187): between two steps it lets the caller's actor go and
  /// stops with `CancellationError` once cancelled — a drag's next position is not queued behind
  /// the whole chain of the one before.
  package func previewChain(from k: Int, params: ParamSet) async throws -> ChainPreview {
    let steps = history.steps
    guard steps.indices.contains(k) else { throw HistoryError.noStep(k) }
    let stop = toolStep(from: k, revising: k, params: params)
    let end = stop ?? steps.count
    if let masked = movedMaskStep(k, params: params, until: end) {
      throw PipelineError.maskMoved(step: masked)
    }
    let input = try chainInput(k, until: end)
    var state = input.state
    for index in k..<end {
      if index > k { await Task.yield() }
      try Task.checkCancellation()
      let recipe = Self.recipe(of: steps[index], revising: index == k ? params : nil)
      // Rendered only before `stop`: its process is registered (an unknown one stops there).
      guard let type = registry.type(id: recipe.processID) else { break }
      // The recorded values as the replay reads them: a refused value stops it with its name.
      let values = try PipelineRunner.values(
        of: PipelineStep(recipe: recipe), schema: type.schema, at: index)
      let step = try runner.applied(
        type.init(params: values, device: device), input: (state.image, state.metadata),
        stats: try state.stats ?? gpuStats.measure(state.image), layers: state.layers,
        layerStats: state.layerStats, roles: state.roles, mask: input.masks[index])
      try state.advance(
        past: step, of: recipe.processID, moving: registry.movingIDs, stack: bundle.layerStats,
        measure: gpuStats)
    }
    // The one read-back of the chain (card 0188): its last image, for the viewer.
    return ChainPreview(image: state.image.image(metadata: state.metadata), stoppedBefore: stop)
  }

  /// The first step from `start` that runs a host tool, step `k` read with `params`, or `nil`.
  ///
  /// Where a revise of `k` stops its replay and the chain preview its render (a process the
  /// registry cannot render counts as a tool). The replay reads values the same way.
  package func toolStep(from start: Int, revising k: Int, params: ParamSet) -> Int? {
    let steps = history.steps
    return steps.indices[min(max(start, 0), steps.count)...].first { index in
      let recipe = Self.recipe(of: steps[index], revising: index == k ? params : nil)
      return registry.type(id: recipe.processID).map(recipe.runsTool(as:)) ?? true
    }
  }

  /// The recipe of applied `step`, with `params` in place of its recorded values when given.
  static func recipe(of step: History.Step, revising params: ParamSet?) -> Recipe {
    Recipe(processID: step.processID, params: params ?? step.params)
  }

  /// The masked step after `k` and before `end` a pixel-moving step `k` would misplace.
  ///
  /// Step `k` moves the pixels under its recorded values or under `params`: the first masked
  /// step's recorded mask would land on other pixels (card 0160). The one rule of the revise's
  /// refusal and of the chain preview's.
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

  /// What step `k` reads and the recorded masks of the steps from it to `end`, read from the
  /// history once per edit (the same `k` and `end` over the same step files).
  func chainInput(_ k: Int, until end: Int) throws -> ChainInput {
    let steps = history.steps
    let files = steps.map(\.file)
    if let chainInput, chainInput.k == k, chainInput.files == files, chainInput.end == end {
      return chainInput
    }
    let before = Array(steps.prefix(k))
    let moving = registry.movingIDs
    let image = try history.image(file: before.last?.file)
    let context = try history.contextAndMoves(
      over: bundleLayers, stats: bundle.layerStats, device: device, moving: moving, before: k)
    // Uploaded once per edit, with the masks, and measured there (card 0188): the chain starts
    // on the GPU.
    let uploaded = try GPUImage(device: device, image: image)
    let state = ChainState(
      image: uploaded, metadata: image.metadata,
      stats: k == 0 ? bundle.stats : try gpuStats.measure(uploaded),
      layers: context.layers, layerStats: context.stats, onlyMoved: context.onlyMoved,
      roles: Set(before.flatMap { $0.outputs.keys }))
    var masks: [Int: GPUImage] = [:]
    for index in steps.indices[k..<end] where steps[index].mask != nil {
      masks[index] = try history.mask(ofStep: index).map { try GPUImage(device: device, image: $0) }
    }
    let input = ChainInput(k: k, end: end, files: files, state: state, masks: masks)
    chainInput = input
    return input
  }
}
