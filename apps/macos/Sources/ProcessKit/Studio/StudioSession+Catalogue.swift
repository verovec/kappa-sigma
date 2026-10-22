/// Why a process cannot be the Studio's next step: shown on the greyed process, never enforced
/// behind the user's back (R2).
package enum StudioUnavailable: Equatable, Sendable {
  /// Layers the process reads are missing (no StarNet step yet, no emission layer…).
  case missing([LayerRole])
  /// A linear process after the stretch.
  case linearAfterStretch
}

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
    try type.init(params: params, device: device)
      .suggestions(stats: stepStats, layers: bundle.layerStats)
  }
}
