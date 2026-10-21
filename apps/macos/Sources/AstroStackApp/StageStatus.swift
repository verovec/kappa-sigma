/// Where a journey stage stands, as the sidebar shows it.
nonisolated package enum StageStatus: Equatable, Sendable {
  /// Why a stage cannot be worked yet.
  package enum Reason: Equatable, Sendable {
    /// No capture night imported.
    case needsSources
    /// No stack yet.
    case needsStack
  }

  /// Nothing done, and nothing in the way.
  case toDo
  /// Its inputs are there; the user may work it.
  case ready
  /// A run is in progress (0057).
  case running
  /// This many things worth a look (calibration gaps, for instance).
  case attention(Int)
  /// Done.
  case done
  /// Not workable before another stage.
  case unavailable(Reason)
}
