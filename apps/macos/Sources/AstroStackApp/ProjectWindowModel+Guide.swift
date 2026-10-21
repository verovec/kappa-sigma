package import RenderKit

/// The first-stack guide of a project window (card 0061): closed until Help › First-Stack Guide,
/// then on the step this project reached.
extension ProjectWindowModel {
  /// The control the guide's step points at, `nil` while closed.
  package var guideTarget: AccessibilityID? {
    guideStep.map { FirstStackGuide.steps[$0].target }
  }

  /// Opens the guide on the step this project last showed (the first one otherwise).
  package func openGuide() {
    let saved = Result { try store()?.setting(FirstStackGuide.settingKey) }
    // A failed read is reported first; a failing write in `showGuideStep` then takes over.
    if case .failure(let failure) = saved { error = UserFacingError(failure) }
    let step = ((try? saved.get()) ?? nil).flatMap(Int.init) ?? 0
    showGuideStep(FirstStackGuide.steps.indices.contains(step) ? step : 0)
  }

  /// Shows step `index` of the open guide (its stage selected) and remembers it; out of range,
  /// nothing.
  package func showGuideStep(_ index: Int) {
    guard FirstStackGuide.steps.indices.contains(index) else { return }
    guideStep = index
    select(FirstStackGuide.steps[index].stage)
    do {
      try store()?.setSetting(FirstStackGuide.settingKey, to: String(index))
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// Closes the guide; the step stays remembered for the next opening.
  package func closeGuide() {
    guideStep = nil
  }
}
