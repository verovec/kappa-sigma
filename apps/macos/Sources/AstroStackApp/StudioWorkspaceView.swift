internal import RenderKit
internal import SwiftUI

/// The Studio (card 0087, design §5 B): the catalogue, the working image (the history's head,
/// or the preview of the panel's values), the panel and the history.
struct StudioWorkspaceView: View {
  let model: StudioWorkspaceModel

  var body: some View {
    HStack(spacing: 0) {
      StudioCatalogueView(model: model).frame(width: 220)
      Divider()
      ViewerView(
        model: model.viewer.model, renderer: model.viewer.renderer,
        texture: model.viewer.texture, reference: model.viewer.reference)
      Divider()
      StudioSideView(model: model).frame(width: 320)
    }
  }
}
