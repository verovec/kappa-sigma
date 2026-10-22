internal import RenderKit
package import SwiftUI

/// The Studio (card 0087, design §5 B): the catalogue, the working image (the history's head,
/// or the preview of the panel's values), the panel and the history.
package struct StudioWorkspaceView: View {
  let model: StudioWorkspaceModel

  /// The Studio of `model`.
  package init(model: StudioWorkspaceModel) {
    self.model = model
  }

  package var body: some View {
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
