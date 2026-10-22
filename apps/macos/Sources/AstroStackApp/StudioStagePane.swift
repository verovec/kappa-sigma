internal import RenderKit
internal import SwiftUI

/// The Studio stage: the latest stack's layers and the viewer, read-only until the finishing
/// processes (E12) land here.
struct StudioStagePane: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    if let workspace = model.workspace {
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader(.app("Studio"), help: StageHelp.help(.studio, locale: locale))
          .padding(DesignMetrics.spacingM)
        StudioWorkspaceView(model: workspace)
      }
    } else if let studio = model.studio {
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader(.app("Studio"), help: StageHelp.help(.studio, locale: locale))
          .padding(DesignMetrics.spacingM)
        HStack(spacing: 0) {
          LayerList(model: studio).frame(width: 260)
          Divider()
          LayerDetail(model: studio)
        }
        .id(studio.source.runID)
      }
    } else {
      EmptyState(
        .app("Studio"),
        message: .app("The stacked image and its finishing processes will appear here."),
        systemImage: "wand.and.stars", help: StageHelp.help(.studio, locale: locale)
      )
      .task { await model.openStudio() }
    }
  }
}
