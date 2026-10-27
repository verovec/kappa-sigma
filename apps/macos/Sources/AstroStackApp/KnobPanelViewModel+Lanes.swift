package import FilterKit
package import StackKit

/// One column per lane kind (card 0121): a lane-scoped knob may differ per lane, a run-wide one
/// keeps the global value and says why; a lane value equal to the global one is no override.
extension KnobPanelViewModel {
  /// Every knob as `lane` stacks it, against the global value (its `defaultValue`, so
  /// `isDefault` = not overridden): a lane knob's lane value, a run-wide knob's global one.
  package func rows(lane: FilterSet) -> [Row] {
    let laneSettings = settings(for: mode, lane: lane)
    return zip(KnobSchema.knobs, rows).map { knob, row in
      Row(
        id: row.id, level: row.level, kind: row.kind, scope: row.scope,
        value: knob.scope == .lane ? knob.value(in: laneSettings) : row.value,
        defaultValue: row.value)
    }
  }

  /// How many lane knobs `lane` overrides.
  package func overrideCount(lane: FilterSet) -> Int {
    lanePatch(lane, mode: mode).values.count
  }

  /// Sets lane knob `id` to `value` for `lane`; a run-wide knob or a refused value is ignored.
  ///
  /// The global value clears the lane's edit: a lane value equal to the global one is no override
  /// and follows the global. A lane value set apart stays as set while the global moves.
  package func set(_ id: String, to value: KnobValue, lane: FilterSet) {
    guard let knob = KnobSchema.knob(id), knob.acceptsLane(value) else { return }
    laneEdits[lane, default: [:]][id] = value == knob.value(in: settings) ? nil : value
  }

  /// Knob `id` of `lane` back to the global value.
  package func reset(_ id: String, lane: FilterSet) {
    laneEdits[lane]?[id] = nil
  }

  /// What a run on the preset of `mode` applies and records; `prepare` keeps the lanes and the
  /// processing only for a scope that splits (`RunKnobs.unsplit` otherwise).
  package func runKnobs(for mode: PreprocessRequest.Mode) -> RunKnobs {
    RunKnobs(
      patch: patch(for: mode),
      lanes: laneEdits.keys.reduce(into: [:]) { lanes, lane in
        let patch = lanePatch(lane, mode: mode)
        if !patch.values.isEmpty { lanes[lane] = patch }
      },
      processing: processing)
  }

  /// The lane values of `lane` that differ from the global settings on the preset of `mode`.
  private func lanePatch(_ lane: FilterSet, mode: PreprocessRequest.Mode) -> KnobPatch {
    let global = settings(for: mode)
    let laneSettings = settings(for: mode, lane: lane)
    var values: [String: KnobValue] = [:]
    for knob in KnobSchema.knobs where knob.scope == .lane {
      let value = knob.value(in: laneSettings)
      if value != knob.value(in: global) { values[knob.id] = value }
    }
    return KnobPatch(values: values)
  }

  /// The global settings on the preset of `mode` with the lane values of `lane`.
  private func settings(for mode: PreprocessRequest.Mode, lane: FilterSet) -> PreprocessSettings {
    Self.applying(laneEdits[lane] ?? [:], to: settings(for: mode))
  }
}
