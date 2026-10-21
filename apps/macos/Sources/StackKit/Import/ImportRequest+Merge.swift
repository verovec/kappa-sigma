extension ImportRequest {
  /// This request with the folders and choices of a later import of the same project added.
  ///
  /// Every earlier override is kept (a night marked dual-band stays so); the later one wins on a
  /// conflict. Folders and lists are unions in order of appearance; an `auto` colour model defers to the
  /// earlier choice; forcing the calibration is the later import's choice, so it can be undone.
  /// Unchecked suggestions and dropped sets stay unions: their ids are per light set, and
  /// undoing one project-wide is the Données stage's (0078).
  package func merging(_ later: ImportRequest) -> ImportRequest {
    var merged = self
    merged.paths = Self.union(paths, later.paths)
    merged.filterMap.merge(later.filterMap) { _, new in new }
    merged.filterSets.merge(later.filterSets) { _, new in new }
    merged.excludeSets = Self.union(excludeSets, later.excludeSets)
    merged.calibExclude = Self.union(calibExclude, later.calibExclude)
    if later.colorModel != .auto { merged.colorModel = later.colorModel }
    merged.forceCalibration = later.forceCalibration
    return merged
  }

  private static func union(_ first: [String], _ second: [String]) -> [String] {
    var seen = Set<String>()
    return (first + second).filter { seen.insert($0).inserted }
  }
}
