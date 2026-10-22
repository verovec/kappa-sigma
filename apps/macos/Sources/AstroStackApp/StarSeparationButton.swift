internal import RenderKit
internal import SwiftUI

/// « Separate stars »: StarNet on the Studio's head, recorded as a history step.
struct StarSeparationButton: View {
  var model: ExportStageModel
  /// What a click does: the separation, unless the caller first leads to the Export stage.
  var action: (() -> Void)?

  var body: some View {
    Button(model.hasStarless ? .app("Separate Stars Again") : .app("Separate Stars")) {
      if let action { action() } else { model.startSeparation() }
    }
    .disabled(model.isSeparating || model.isExporting)
    .accessible(.stageControl("export", "separate"), label: .app("Separate Stars"))
  }
}
