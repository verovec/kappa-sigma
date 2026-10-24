package import StackKit

/// The panel's values a run applies and records (card 0121): the patch on the preset, the lane
/// overrides of a split run and what follows its stack.
package struct RunKnobs: Equatable, Sendable {
  /// The knobs moved from the preset.
  package var patch: KnobPatch
  /// The lane-scoped knobs each kind of lane takes over the global values.
  package var lanes: [FilterSet: KnobPatch] = [:]
  /// What follows the stack.
  package var processing = StackProcessing.single

  /// A record's own values, as it ran.
  package init(_ record: StackRecord) {
    self.init(patch: record.knobs, lanes: record.laneKnobs, processing: record.processing)
  }

  /// Values from the panel.
  package init(
    patch: KnobPatch, lanes: [FilterSet: KnobPatch] = [:],
    processing: StackProcessing = .single
  ) {
    self.patch = patch
    self.lanes = lanes
    self.processing = processing
  }

  /// The values of a run that does not split: no lane, one flow.
  package var unsplit: Self { Self(patch: patch) }
}
