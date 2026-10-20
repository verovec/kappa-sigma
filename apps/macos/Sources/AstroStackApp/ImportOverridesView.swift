internal import StackKit
internal import SwiftUI

/// The overrides that act on the whole scan: colour model, filter map, excluded sets.
struct ImportOverridesView: View {
  var model: ImportViewModel

  var body: some View {
    GroupBox("Overrides") {
      VStack(alignment: .leading, spacing: 8) {
        Picker(
          "Colour model",
          selection: Binding(get: { model.request.colorModel }, set: { model.setColorModel($0) })
        ) {
          ForEach(ColorChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        if let plan = model.plan {
          Text("Scan verdict: \(plan.inventory.colorModel.rawValue)")
            .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(model.lightFilters, id: \.self) { filter in filterMap(filter) }
        ForEach(model.excludedRows) { row in
          HStack {
            Text("Excluded: \(row.type.rawValue) \(row.filter) · \(row.count) frames")
            Button("Restore") { model.restore(row) }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// One light filter and the channel it stacks into.
  private func filterMap(_ filter: String) -> some View {
    Picker(
      "Filter \(filter) →",
      selection: Binding(
        get: { model.request.filterMap[filter] ?? "" },
        set: { model.mapFilter(filter, to: $0.isEmpty ? nil : $0) })
    ) {
      Text("as detected").tag("")
      ForEach(ImportViewModel.channels, id: \.self) { Text($0).tag($0) }
    }
    .fixedSize()
  }
}
