/// The stage states of a project, derived from its facts and nothing else.
///
/// Deriving never selects a stage: the sidebar shows where the project stands and the user goes
/// where they want (an astrophotographer returns to Tri after looking at the result).
nonisolated package enum JourneyState {
  /// Every stage's status for `facts`.
  package static func derive(from facts: ProjectFacts) -> [JourneyStage: StageStatus] {
    Dictionary(uniqueKeysWithValues: JourneyStage.allCases.map { ($0, status($0, facts)) })
  }

  private static func status(_ stage: JourneyStage, _ facts: ProjectFacts) -> StageStatus {
    let summary = facts.summary
    let hasSources = summary.sources > 0
    switch stage {
    case .data:
      return hasSources ? .done : .toDo
    case .calibration:
      guard hasSources else { return .unavailable(.needsSources) }
      switch facts.calibrationGaps {
      case nil: return .ready
      case 0: return .done
      case let gaps?: return .attention(gaps)
      }
    case .review:
      guard hasSources else { return .unavailable(.needsSources) }
      return facts.framesReviewed ? .done : .ready
    case .stacking:
      guard hasSources else { return .unavailable(.needsSources) }
      if facts.stacksRunning > 0 { return .running }
      return summary.stacks > 0 ? .done : .ready
    case .studio:
      guard summary.images > 0 else { return .unavailable(.needsStack) }
      return summary.historySteps > 0 ? .done : .ready
    case .export:
      guard summary.images > 0 else { return .unavailable(.needsStack) }
      return facts.deliverables > 0 ? .done : .ready
    }
  }
}
