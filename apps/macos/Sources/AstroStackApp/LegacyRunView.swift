import RenderKit
package import SwiftUI

/// The Layers sidebar and the viewer of the selected layer.
package struct LegacyRunView: View {
  let model: LegacyRunModel

  /// The sidebar starts on the layer the model already shows.
  package init(model: LegacyRunModel) {
    self.model = model
  }

  package var body: some View {
    NavigationSplitView {
      LayerList(model: model)
        .navigationTitle(Text(.app("Layers")))
        .frame(minWidth: 240)
    } detail: {
      LayerDetail(model: model)
    }
  }
}
