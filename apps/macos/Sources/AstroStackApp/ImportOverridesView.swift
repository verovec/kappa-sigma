internal import StackKit
internal import SwiftUI

/// The overrides that act on the whole scan: colour model, filter map, excluded sets.
struct ImportOverridesView: View {
  var model: ImportViewModel
  @Environment(\.locale) private var locale

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        colorModel
        ForEach(model.lightFilters, id: \.self) { filter in filterMap(filter) }
        ForEach(model.excludedRows) { row in excluded(row) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(.app("Overrides"))
    }
  }

  /// The colour-model choice and, beside it, what the scan measured.
  @ViewBuilder private var colorModel: some View {
    Picker(
      selection: Binding(get: { model.request.colorModel }, set: { model.setColorModel($0) })
    ) {
      ForEach(ColorChoice.allCases, id: \.self) { Text(verbatim: label($0.termID)).tag($0) }
    } label: {
      Text(.app("Colour model"))
    }
    .pickerStyle(.segmented)
    .fixedSize()
    if let plan = model.plan {
      Text(.app("Scan verdict: \(label(plan.inventory.colorModel.termID))"))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  /// An excluded set, and the button that puts it back.
  private func excluded(_ row: ImportPlan.SetRow) -> some View {
    HStack {
      let type = label(row.type.termID)
      Text(.app("Excluded: \(type) \(row.filter) · \(AstroFormat.frameCount(row.count))"))
      Button(.app("Restore")) { model.restore(row) }
    }
  }

  /// A glossary term in the view's language.
  private func label(_ id: String) -> String {
    AppGlossary.label(id, locale: locale)
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
