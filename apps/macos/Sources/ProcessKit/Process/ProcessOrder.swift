/// The usual order of the Studio's processes (card 0116): one list, the catalogue sorts by it and
/// « usually next » reads it — a suggestion only, nothing greyed nor reordered (R2).
///
/// Linear work first (combination, background, calibration, colour, noise, HDR), then the
/// stretch, then the finish; geometry fits anywhere and is never suggested.
package enum ProcessOrder {
  /// Every registered process once, in the usual order (`ProcessOrderTests` pins it).
  package static let usual = [
    ChannelCombinationProcess.id, BackgroundExtractionProcess.id, PlateSolveProcess.id,
    ColourCalibrationProcess.id, ColourBalanceProcess.id, SkyDesatProcess.id, DenoiseProcess.id,
    LineInjectionProcess.id,
    HDRProcess.id, StretchProcess.id, LevelsProcess.id, CurvesProcess.id,
    EmissionScreensProcess.id, SaturationProcess.id, StarRecompositionProcess.id,
    GeometryProcess.id,
  ]

  /// The process that fits anywhere: no rank, never « usually next ».
  private static let anywhere: Set<String> = [GeometryProcess.id]

  /// Rank by id, the order's processes but `anywhere`.
  private static let ranks: [String: Int] = Dictionary(
    uniqueKeysWithValues: usual.enumerated().filter { !anywhere.contains($0.element) }
      .map { ($0.element, $0.offset + 1) })

  /// The 1-based rank of process `id` in the usual order; `nil` for geometry (anywhere) and for a
  /// process outside the order (a batch step such as StarNet).
  package static func rank(of id: String) -> Int? {
    ranks[id]
  }

  /// The process usually applied after the steps `applied` (process ids, oldest first): the
  /// first one ranked after the furthest step reached — so a plate solve after the stretch does
  /// not send the hint back to linear work — that `skipping` (the greyed ones) leaves; the first
  /// one for an empty history, `nil` past the last.
  package static func usuallyNext(after applied: [String], skipping: Set<String> = []) -> String? {
    let reached = applied.compactMap { rank(of: $0) }.max() ?? 0
    return usual.first { id in
      (rank(of: id) ?? 0) > reached && !skipping.contains(id)
    }
  }
}
