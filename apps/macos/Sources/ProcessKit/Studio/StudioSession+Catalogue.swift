extension StudioSession {
  /// Why `type` cannot be the next step, or `nil`: the `Pipeline.problems` rules (required
  /// layers, linear after non-linear) over the steps so far.
  package func unavailable(
    for type: any ImageProcess.Type, base: Set<LayerRole>, registry: ProcessRegistry
  ) -> StudioUnavailable? {
    let present = presentRoles(base: base)
    let missing = type.requires.filter { !present.contains($0) }
    if !missing.isEmpty { return .missing(missing) }
    if type.requiresSolution, history.current.metadata.wcs == nil { return .unsolved }
    let stretched = history.steps.contains { step in
      registry.type(id: step.processID).map(Pipeline.leavesNonLinear) ?? false
    }
    return type.stage == .linear && stretched ? .linearAfterStretch : nil
  }

  /// What `type` with `params` proposes from the statistics of the next step — or, for applied
  /// step `step` being edited, from what that step read (card 0172): values the panel offers,
  /// never sets (R2).
  package func suggestions(
    for type: any ImageProcess.Type, params: ParamSet, before step: Int? = nil
  ) throws -> [Suggestion] {
    let (stats, layers) = try suggestionInputs(before: step)
    let process = try type.init(params: params, device: device)
    return process.suggestions(stats: stats, layers: layers)
  }

  /// The input statistics and the layer statistics applied step `step` read; the head's, which
  /// the next step reads, without one.
  ///
  /// Step 0 read the stack itself. A later step's are the chain preview's input once the edit
  /// holds it (`chainInput`), else read from the history as that input is.
  private func suggestionInputs(before step: Int?) throws -> (LayerStats, [String: LayerStats]) {
    let steps = history.steps
    guard let step, steps.indices.contains(step) else { return (stepStats, try context().1) }
    if step == 0 { return (bundle.stats, bundle.layerStats) }
    if let chainInput, chainInput.k == step, chainInput.files == steps.map(\.file),
      let stats = chainInput.state.stats
    {
      return (stats, chainInput.state.layerStats)
    }
    let layers = try history.context(
      over: bundleLayers, stats: bundle.layerStats, device: device, moving: registry.movingIDs,
      before: step
    ).1
    let input = try history.image(file: steps[step - 1].file)
    return (LayerStats.measured(input), layers)
  }
}
