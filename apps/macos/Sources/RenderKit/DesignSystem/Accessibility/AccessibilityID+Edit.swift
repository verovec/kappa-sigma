// MARK: - Re-editing a step and the history versions (card 0159)

extension AccessibilityID {
  /// The eye button of a Studio history row: compare the viewer with that step's output.
  package static func studioStepCompare(_ index: Int) -> Self {
    stageControl("studio", "step." + String(index) + ".compare")
  }

  /// « Cancel » of the edit of an applied step.
  package static let studioEditCancel = stageControl("studio", "edit.cancel")

  /// « Apply change » of the edit of an applied step (a revise).
  package static let studioEditApply = stageControl("studio", "edit.apply")

  /// The Versions menu above the Studio's history.
  package static let studioVersions = stageControl("studio", "versions")

  /// An action on version `index` of the Versions menu: `compare`, `restore` or `drop`.
  package static func studioVersion(_ index: Int, _ action: String) -> Self {
    stageControl("studio", "versions." + String(index) + "." + action)
  }
}
