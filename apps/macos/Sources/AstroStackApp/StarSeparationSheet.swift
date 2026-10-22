internal import RenderKit
package import SwiftUI

/// StarNet's progress, with Cancel (StarNet is stopped, nothing is recorded).
package struct StarSeparationSheet: View {
  var model: ExportStageModel

  /// The progress sheet of the separation that `model` runs.
  package init(model: ExportStageModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      Text(.app("Separating the stars with StarNet…")).font(.headline)
      ProgressView(value: model.progress.last ?? 0)
      HStack {
        Spacer()
        Button(.app("Cancel"), role: .cancel) { model.cancelSeparation() }
          .keyboardShortcut(.cancelAction)
          .accessible(.stageControl("export", "cancelSeparation"), label: .app("Cancel"))
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(width: 380)
  }
}
