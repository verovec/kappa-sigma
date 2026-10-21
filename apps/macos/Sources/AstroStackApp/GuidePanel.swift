internal import RenderKit
package import SwiftUI

/// The first-stack guide's side panel (card 0061): the step's text, Back, Next and Close; the
/// control the step points at is ringed in the window (`guideTarget`).
package struct GuidePanel: View {
  let model: ProjectWindowModel
  let step: Int
  @Environment(\.locale) private var locale

  /// The panel of the guide of `model`, on `step`.
  package init(model: ProjectWindowModel, step: Int) {
    self.model = model
    self.step = step
  }

  package var body: some View {
    let count = FirstStackGuide.steps.count
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      Text(.app("Step \(step + 1) of \(count)"))
        .font(DesignMetrics.captionFont).foregroundStyle(DesignColor.textSecondary.color)
      HelpText(FirstStackGuide.text(step, locale: locale))
      HStack {
        Button(.app("Back")) { model.showGuideStep(step - 1) }
          .disabled(step == 0)
          .accessible(.guide("back"), label: .app("Back"))
        Button(.app("Next")) { model.showGuideStep(step + 1) }
          // No Return shortcut: on the Stacking step, Run is the window's default action.
          .disabled(step + 1 == count)
          .accessible(.guide("next"), label: .app("Next"))
        Spacer()
        Button(.app("Close")) { model.closeGuide() }
          .accessible(.guide("close"), label: .app("Close"))
      }
      Spacer()
    }
    .padding(DesignMetrics.spacingL)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
