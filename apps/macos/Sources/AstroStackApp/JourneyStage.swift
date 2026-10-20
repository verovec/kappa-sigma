/// The stages of a project, in the order an astrophotographer works them (E20 goal 1).
///
/// Card 0074 seeds the list so the glossary words each stage once; card 0076 builds the sidebar
/// and the stage states on it. Never re-declare the stages elsewhere.
package enum JourneyStage: String, CaseIterable, Sendable {
  /// Nights, lights per filter, integration, calibration coverage.
  case data
  /// The masters (0071).
  case calibration
  /// Frame review (0069).
  case review
  /// Settings and run (0057, 0070).
  case stacking
  /// The finishing processes (E12, E13).
  case studio
  /// The deliverables (0055).
  case export
}
