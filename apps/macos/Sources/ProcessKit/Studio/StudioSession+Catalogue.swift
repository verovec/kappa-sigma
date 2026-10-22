extension StudioSession {
  /// Why `type` cannot be the next step (a layer it needs is missing, or it is linear after the
  /// stretch), or `nil`: the `Pipeline.problems` rule over the steps so far, shown on the greyed
  /// process, never enforced behind the user's back (R2).
  package func unavailableReason(
    for type: any ImageProcess.Type, base: Set<LayerRole>, registry: ProcessRegistry
  ) throws -> String? {
    let present = try presentRoles(base: base)
    let steps = history.steps.map {
      PipelineStep(recipe: Recipe(processID: $0.processID, params: $0.params))
    }
    let candidate = PipelineStep(
      recipe: Recipe(processID: type.id, params: ParamSet(schema: type.schema)))
    let index = steps.count + 1
    let problems = Pipeline(name: "studio", steps: steps + [candidate])
      .problems(registry: registry, present: present)
      .filter { $0.hasPrefix("step \(index) ") }
    guard let first = problems.first, let colon = first.range(of: "): ") else { return nil }
    return String(first[colon.upperBound...])
  }

  /// What `type` with `params` proposes from the statistics of the next step: values the panel
  /// offers, never sets (R2).
  package func suggestions(for type: any ImageProcess.Type, params: ParamSet) throws
    -> [Suggestion]
  {
    try type.init(params: params, device: device)
      .suggestions(stats: stepStats, layers: bundle.layerStats)
  }
}
