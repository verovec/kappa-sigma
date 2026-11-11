/// Why the Stacking stage does not offer Run, each with the one action that lifts it.
package enum RunBlocker: Equatable, Sendable {
  /// The project has no source at all.
  case noNight
  /// Its only sources are imported legacy runs: shown, never stacked again.
  case legacyRunsOnly
  /// Masters and stacks are written inside the package: it must be saved first.
  case unsaved
  /// The scan lists series and none is checked.
  case noSeriesChecked
  /// Its stacks show several objects and no scan lists the series yet.
  case seriesUnknown
}

extension ProjectWindowModel {
  /// Why Run is not offered, the first reason that holds; `nil` when nothing of the project
  /// holds it back (a run going, or a rescan awaited, greys it without a notice).
  ///
  /// A night read from a bucket is a night (card 0190): a project of bucket prefixes alone is
  /// never told to import one.
  package var runBlocker: RunBlocker? {
    if nightPaths.isEmpty { return sources.isEmpty ? .noNight : .legacyRunsOnly }
    if needsSave { return .unsaved }
    if !series.isEmpty && series.scopes.isEmpty { return .noSeriesChecked }
    return needsSeries ? .seriesUnknown : nil
  }
}
