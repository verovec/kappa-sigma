package import FilterKit

extension PreprocessRequest {
  /// Sets the lane-scoped knobs `patch` for every lane of kind `lane` (card 0121); a run-wide,
  /// unknown or refused knob throws and nothing is recorded.
  ///
  /// Only a split run has kinds of lanes: an unsplit one never applies an override.
  package mutating func overrideLane(_ lane: FilterSet, with patch: KnobPatch) throws(KnobError) {
    try KnobSchema.validateLane(patch)
    laneOverrides[lane] = patch.values.isEmpty ? nil : patch
  }

  /// The settings `lane` of `plan` stacks with: the run's, with its kind's override when the run
  /// splits — exactly the run's otherwise.
  package func settings(forLane lane: String, in plan: NightPlan) -> PreprocessSettings {
    guard FilterSetLanes.dualbandLane(in: plan.channels.keys) != nil else { return settings }
    let kind: FilterSet = FilterSetLanes.baseFilter(of: lane) == lane ? .broadband : .dualband
    guard let patch = laneOverrides[kind] else { return settings }
    // Validated on entry (`overrideLane`): every knob is a lane knob and accepts its value.
    return (try? KnobSchema.apply(patch, to: settings)) ?? settings
  }
}
