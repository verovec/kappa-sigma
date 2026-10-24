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
    HDRProcess.id, StretchProcess.id, LevelsProcess.id, CurvesProcess.id,
    EmissionScreensProcess.id, SaturationProcess.id, StarRecompositionProcess.id,
    GeometryProcess.id,
  ]

  /// The process that fits anywhere: never « usually next ».
  private static let anywhere: Set<String> = [GeometryProcess.id]

  /// The 1-based rank of process `id` in the usual order, `nil` for one outside it.
  package static func rank(of id: String) -> Int? {
    usual.firstIndex(of: id).map { $0 + 1 }
  }

  /// The process usually applied after the steps `applied` (process ids, oldest first): the one
  /// after the last ordered step, geometry and processes outside the order skipped; the first one
  /// for an empty history, `nil` past the last.
  package static func usuallyNext(after applied: [String]) -> String? {
    let last = applied.last { usual.contains($0) && !anywhere.contains($0) }
    let start = last.flatMap { usual.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
    return usual[start...].first { !anywhere.contains($0) }
  }
}
