internal import RenderKit
package import SwiftUI

/// The content of a project window: the journey sidebar (Données → … → Export, each stage with
/// its state) and the selected stage's pane.
///
/// The sidebar shows where the project stands; only the user moves the selection.
package struct ProjectWindowView: View {
  @State var model: ProjectWindowModel

  /// A window showing the project behind `model`.
  package init(model: ProjectWindowModel) {
    _model = State(initialValue: model)
  }

  package var body: some View {
    NavigationSplitView {
      JourneySidebar(model: model)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
    } detail: {
      VStack(spacing: 0) {
        StagePane.pane(for: model.selection, model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let error = model.error {
          StatusBadge(.error, error.message)
            .padding(DesignMetrics.spacingS)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(minWidth: 640, minHeight: 400)
    .sheet(
      isPresented: Binding(
        get: { model.importing != nil }, set: { if !$0 { model.closeImport() } })
    ) {
      if let importing = model.importing {
        ImportSheet(
          model: importing, onAdd: { model.add($0) }, onCancel: { model.closeImport() },
          addError: model.error)
      }
    }
  }
}
