internal import SwiftUI

/// The layers of a stack or legacy run; choosing one loads it into the viewer.
struct LayerList: View {
  let model: LegacyRunModel
  @State private var selection: String?
  @Environment(\.locale) private var locale

  init(model: LegacyRunModel) {
    self.model = model
    _selection = State(initialValue: model.selected)
  }

  var body: some View {
    List(model.rows(locale: locale), selection: $selection) { row in
      VStack(alignment: .leading) {
        Text(verbatim: row.name).font(.headline)
        Text(verbatim: row.detail).font(.caption).foregroundStyle(.secondary)
      }
    }
    .task(id: selection) { await load(selection) }
    // A layer selected by the model (`-openRun` shows the base) is highlighted too.
    .onChange(of: model.selected) { _, shown in selection = shown }
  }

  /// Loads the chosen layer.
  ///
  /// Choosing another cancels a load still running; a failure shows in `model.failure`.
  private func load(_ id: String?) async {
    guard let id else { return }
    try? await model.select(id)
  }
}
