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

  /// What `type` with `params` proposes from the statistics of the next step — or, for the
  /// applied step 0 being edited (`step`), from the stack it read (card 0172): values the panel
  /// offers, never sets (R2).
  ///
  /// Only step 0's inputs are held without a read (the bundle's own statistics); a later step
  /// being edited is offered the head's, as before — reading its inputs back from the history
  /// would block the caller on full-resolution files.
  package func suggestions(
    for type: any ImageProcess.Type, params: ParamSet, before step: Int? = nil
  ) throws -> [Suggestion] {
    let process = try type.init(params: params, device: device)
    if step == 0, !history.steps.isEmpty {
      return process.suggestions(stats: bundle.stats, layers: bundle.layerStats)
    }
    return process.suggestions(stats: stepStats, layers: try context().1)
  }
}
