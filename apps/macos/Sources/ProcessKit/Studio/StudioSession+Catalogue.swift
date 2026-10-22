extension StudioSession {
  /// Why `type` cannot be the next step, or `nil`: the `Pipeline.problems` rules (required
  /// layers, linear after non-linear) over the steps so far.
  package func unavailable(
    for type: any ImageProcess.Type, base: Set<LayerRole>, registry: ProcessRegistry
  ) -> StudioUnavailable? {
    let present = presentRoles(base: base)
    let missing = type.requires.filter { !present.contains($0) }
    if !missing.isEmpty { return .missing(missing) }
    let stretched = history.steps.contains { step in
      registry.type(id: step.processID).map(Pipeline.leavesNonLinear) ?? false
    }
    return type.stage == .linear && stretched ? .linearAfterStretch : nil
  }

  /// What `type` with `params` proposes from the statistics of the next step: values the panel
  /// offers, never sets (R2).
  package func suggestions(for type: any ImageProcess.Type, params: ParamSet) throws
    -> [Suggestion]
  {
    var layers = bundle.layerStats
    for (role, image) in try history.layers() { layers[role.rawValue] = LayerStats.measured(image) }
    let process = try type.init(params: params, device: device)
    return process.suggestions(stats: stepStats, layers: layers)
  }
}
