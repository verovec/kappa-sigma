package import FilterKit

/// What the user asserted about a scan (`inspect.ScanOptions` + the run's colour knob).
///
/// Every override is visible and wins over detection (R2): detection only fills the blanks.
package struct InspectOverrides: Equatable, Sendable {
  /// Signal-based filter detection for unlabeled lights, and wheel-transition flags.
  package var detectChannels = true
  package var channel = ChannelDetector.Options()
  /// Filter → channel; `""` or `ignore` drops those lights.
  package var filterMap: [String: String] = [:]
  /// Set ids (from a default scan) whose frames the user dropped; applied before `filterMap`.
  package var excludeSets: [String] = []
  /// Light set id → clip filter of a one-shot-colour night.
  package var filterSets: [String: FilterSet] = [:]
  /// Mono or colour stack, `auto` defers to the scan's verdict.
  package var colorModel = ColorChoice.auto

  /// No override: what a default scan does.
  package init() {}
}
