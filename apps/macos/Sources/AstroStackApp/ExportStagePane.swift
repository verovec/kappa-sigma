internal import RenderKit
internal import SwiftUI

/// The Export stage (card 0091): the chosen stack's Studio head, star separation, the
/// deliverable set and the exports recorded; empty while the Studio's image loads.
struct ExportStagePane: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(spacing: 0) {
      if model.stacks.count > 1 { StackPicker(model: model) }
      if let export = model.exportStage {
        ExportStageView(model: export)
        // Once an export is made, the frames downloaded for it can go (card 0192).
        if model.offersKeptFramesRemoval {
          KeptFramesLine(model: model).padding([.horizontal, .bottom], DesignMetrics.spacingM)
        }
      } else {
        EmptyState(
          .app("Export"),
          message: .app("The deliverables written from the finished image will appear here."),
          systemImage: "square.and.arrow.up", help: StageHelp.help(.export, locale: locale)
        )
        // The export is of the Studio's image: opening the stage opens it (another pick too).
        .task(id: model.selectedStack?.id) {
          if model.studio == nil { await model.openStudio() } else { model.retryWorkspace() }
        }
      }
    }
  }
}
