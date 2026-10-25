internal import RenderKit
package import SwiftUI

/// The Studio (card 0087, design §5 B): the pipeline and the catalogue, the working image (the history's head,
/// or the preview of the panel's values), the panel and the history.
package struct StudioWorkspaceView: View {
  let model: StudioWorkspaceModel

  /// The Studio of `model`.
  package init(model: StudioWorkspaceModel) {
    self.model = model
  }

  package var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        // Which history the column works on (card 0119), only when there is a choice.
        if !model.selections.isEmpty {
          StudioChannelSwitcher(model: model)
          Divider()
        }
        // The pipeline on top of the left column (card 0088), the catalogue under it.
        if let pipeline = model.pipeline {
          ScrollView { PipelineSidebarView(model: pipeline) }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
          Divider()
        }
        StudioCatalogueView(model: model)
      }
      .frame(width: 260)
      Divider()
      ViewerView(
        model: model.viewer.model, renderer: model.viewer.renderer,
        texture: model.viewer.texture, reference: model.viewer.reference)
      Divider()
      StudioSideView(model: model).frame(width: 320)
    }
  }
}
