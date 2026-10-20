internal import StackKit
internal import SwiftUI

/// The overrides that act on the whole scan: colour model, filter map, excluded sets.
struct ImportOverridesView: View {
  var model: ImportViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        Picker(
          selection: Binding(get: { model.request.colorModel }, set: { model.setColorModel($0) })
        ) {
          ForEach(ColorChoice.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
        } label: {
          Text(.app("Colour model"))
        }
        .pickerStyle(.segmented)
        .fixedSize()
        if let plan = model.plan {
          Text(.app("Scan verdict: \(plan.inventory.colorModel.rawValue)"))
            .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(model.lightFilters, id: \.self) { filter in filterMap(filter) }
        ForEach(model.excludedRows) { row in
          HStack {
            Text(
              .app(
                "Excluded: \(row.type.rawValue) \(row.filter) · \(ImportFormat.frames(row.count))"))
            Button(.app("Restore")) { model.restore(row) }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(.app("Overrides"))
    }
  }

  /// One light filter and the channel it stacks into.
  private func filterMap(_ filter: String) -> some View {
    Picker(
      selection: Binding(
        get: { model.request.filterMap[filter] ?? "" },
        set: { model.mapFilter(filter, to: $0.isEmpty ? nil : $0) })
    ) {
      Text(.app("as detected")).tag("")
      ForEach(ImportViewModel.channels, id: \.self) { channel in
        Group {
          if channel == ImportViewModel.ignored {
            Text(.app("ignore"))
          } else {
            Text(verbatim: channel)
          }
        }
        .tag(channel)
      }
    } label: {
      Text(.app("Filter \(filter) →"))
    }
    .fixedSize()
  }
}
