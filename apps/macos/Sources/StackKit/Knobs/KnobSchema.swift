/// Every preprocessing knob a run reads, once (card 0070): the single source the Stacking panel
/// renders from and the only way a patch reaches `PreprocessSettings`.
///
/// Simple = the stacking rejection and its sigmas, the weighting, 2-pass registration, framing
/// (edge and coverage crops), the grading thresholds and the trail mask; everything else is
/// advanced, never hidden (R2). Finishing knobs of the legacy surface belong to the ProcessKit
/// processes (E12), its native-engine knobs were not ported:
/// `Tests/StackKitTests/Fixtures/knobs/legacy-deepsky-knobs.json` accounts for each key.
package enum KnobSchema {
  /// The knobs, in panel order.
  package static let knobs: [Knob] = stack + grading + run

  /// The id of the frame-review breakpoint knob (card 0069): the Tri stage toggles it too.
  package static let frameReviewID = "frame_review"

  /// The id of the reference-pin breakpoint knob (card 0096): the Tri stage toggles it too.
  package static let referenceBreakpointID = "reference_breakpoint"

  /// The knob `id`, or `nil`.
  package static func knob(_ id: String) -> Knob? {
    knobs.first { $0.id == id }
  }

  /// `settings` with `patch` applied; an unknown id or a refused value throws and nothing is
  /// applied.
  package static func apply(_ patch: KnobPatch, to settings: PreprocessSettings) throws
    -> PreprocessSettings
  {
    var applied = settings
    for (id, value) in patch.values.sorted(by: { $0.key < $1.key }) {
      guard let knob = knob(id) else { throw KnobError.unknown(id) }
      try knob.apply(value, to: &applied)
    }
    return applied
  }

  /// Refuses a lane's patch (card 0121) holding a knob that is unknown, run-wide or set to a value
  /// it does not accept: a lane never moves the shared canvas.
  package static func validateLane(_ patch: KnobPatch) throws(KnobError) {
    for (id, value) in patch.values.sorted(by: { $0.key < $1.key }) {
      guard let knob = knob(id) else { throw .unknown(id) }
      guard knob.scope == .lane else { throw .runWide(id) }
      guard knob.accepts(value) else { throw .invalid(id: id, value: value.description) }
    }
  }

  /// The knobs of `settings` that differ from the preset of `mode`: what a run records.
  package static func patch(from settings: PreprocessSettings, mode: PreprocessRequest.Mode)
    -> KnobPatch
  {
    let preset = PreprocessSettings.preset(mode)
    var values: [String: KnobValue] = [:]
    for knob in knobs where knob.value(in: settings) != knob.value(in: preset) {
      values[knob.id] = knob.value(in: settings)
    }
    return KnobPatch(values: values)
  }
}
