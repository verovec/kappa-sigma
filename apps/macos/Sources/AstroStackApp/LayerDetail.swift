internal import RenderKit
internal import SwiftUI

/// The viewer of the shown layer, or why there is none.
struct LayerDetail: View {
  let model: LegacyRunModel

  var body: some View {
    VStack(spacing: 0) {
      if let failure = model.failure {
        StatusBadge(.error, failure)
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
      }
      if let viewer = model.viewer {
        ViewerView(
          model: viewer.model, renderer: viewer.renderer, texture: viewer.texture,
          reference: nil
        )
        .id(model.selected)
      } else {
        ContentUnavailableView {
          Label {
            Text(.app("Choose a layer"))
          } icon: {
            Image(systemName: "square.3.layers.3d")
          }
        } description: {
          Text(.app("Read-only: nothing in the run folder is ever written."))
        }
      }
    }
  }
}
