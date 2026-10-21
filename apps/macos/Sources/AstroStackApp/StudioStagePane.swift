internal import RenderKit
internal import SwiftUI

/// The Studio stage: the latest stack's layers and the viewer, read-only until the finishing
/// processes (E12) land here.
struct StudioStagePane: View {
  var model: ProjectWindowModel

  var body: some View {
    if let studio = model.studio {
      HStack(spacing: 0) {
        LayerList(model: studio).frame(width: 260)
        Divider()
        LayerDetail(model: studio)
      }
      .id(studio.source.runID)
    } else {
      EmptyState(
        .app("Studio"),
        message: .app("The stacked image and its finishing processes will appear here."),
        systemImage: "wand.and.stars"
      )
      .task { await model.openStudio() }
    }
  }
}
