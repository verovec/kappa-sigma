import RenderKit
package import SwiftUI

/// The Layers sidebar and the viewer of the selected layer.
package struct LegacyRunView: View {
  let model: LegacyRunModel
  @State private var selection: String?

  /// The sidebar starts on the layer the model already shows.
  package init(model: LegacyRunModel) {
    self.model = model
    _selection = State(initialValue: model.selected)
  }

  package var body: some View {
    NavigationSplitView {
      List(model.rows, selection: $selection) { row in
        VStack(alignment: .leading) {
          Text(row.name).font(.headline)
          Text(row.detail).font(.caption).foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Layers")
      .frame(minWidth: 240)
      .task(id: selection) { await load(selection) }
      // A layer selected by the model (`-openRun` shows the base) is highlighted too.
      .onChange(of: model.selected) { _, shown in selection = shown }
    } detail: {
      VStack(spacing: 0) {
        if let failure = model.failure {
          Label(failure, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red).padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        if let viewer = model.viewer {
          ViewerView(
            model: viewer.model, renderer: viewer.renderer, texture: viewer.texture,
            reference: nil
          )
          .id(model.selected)
        } else {
          ContentUnavailableView(
            "Choose a layer", systemImage: "square.3.layers.3d",
            description: Text("Read-only: nothing in the run folder is ever written."))
        }
      }
    }
  }

  /// Loads the chosen layer.
  ///
  /// Choosing another cancels a load still running; a failure shows in `model.failure`.
  private func load(_ id: String?) async {
    guard let id else { return }
    try? await model.select(id)
  }
}
