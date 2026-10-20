package import SwiftUI

/// The content of a project window: its sources, and the Import sheet.
///
/// The Studio cards fill the rest.
package struct ProjectWindowView: View {
  @State var model: ProjectWindowModel

  /// A window showing the project behind `model`.
  package init(model: ProjectWindowModel) {
    _model = State(initialValue: model)
  }

  package var body: some View {
    VStack(spacing: 0) {
      if model.sources.isEmpty {
        ContentUnavailableView {
          Label("Empty project", systemImage: "sparkles")
        } description: {
          Text("Import a capture night to see how it will be calibrated and stacked.")
        } actions: {
          importButton
        }
      } else {
        List(model.sources, id: \.id) { source in
          Label(source.path, systemImage: "folder")
        }
        HStack {
          Spacer()
          importButton
        }
        .padding(8)
      }
      if let error = model.error {
        Text(error).foregroundStyle(.red).padding(8)
      }
    }
    .frame(minWidth: 640, minHeight: 400)
    .sheet(
      isPresented: Binding(
        get: { model.importing != nil }, set: { if !$0 { model.importing = nil } })
    ) {
      if let importing = model.importing {
        ImportSheet(
          model: importing, onAdd: { model.add($0) }, onCancel: { model.importing = nil },
          addError: model.error)
      }
    }
  }

  private var importButton: some View {
    Button("Import Captures…") { model.startImport() }
  }
}
