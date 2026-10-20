internal import StackKit
internal import SwiftUI

/// The scan, night by night: one row per frame set, with its overrides beside it.
struct ImportInventoryView: View {
  var model: ImportViewModel
  var plan: ImportPlan

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(plan.nights) { night in
        GroupBox {
          Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
              ForEach(Self.columns.indices, id: \.self) {
                Text(Self.columns[$0]).font(.caption).foregroundStyle(.secondary)
              }
              Text(verbatim: "")  // above the Exclude buttons
            }
            ForEach(night.sets) { row in setRow(row) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
          Text(ImportFormat.night(night.session))
        }
      }
    }
  }

  static let columns: [LocalizedStringResource] = [
    .app("Type"), .app("Object"), .app("Filter"), .app("Exposure"), .app("Sensor"),
    .app("Temp."), .app("Frames"), .app("Filter set"),
  ]

  private func setRow(_ row: ImportPlan.SetRow) -> some View {
    GridRow {
      Text(verbatim: row.type.rawValue)
      Text(verbatim: row.key.object.isEmpty ? "—" : row.key.object)
      Text(verbatim: row.filter.isEmpty ? "—" : row.filter)
      Text(verbatim: ImportFormat.exposure(row.key.exposureMs)).monospacedDigit()
      Text(verbatim: ImportFormat.sensor(row.key)).monospacedDigit()
      Text(verbatim: ImportFormat.temperature(row.key)).monospacedDigit()
      Text(verbatim: "\(row.count)").monospacedDigit()
      filterSet(row)
      Button(.app("Exclude")) { model.exclude(row) }
        .disabled(!model.canExclude(row))
        .help(
          model.canExclude(row)
            ? Text(.app("Drop every frame of this set from the stack"))
            : Text(
              .app("This filter may come from the filter map: exclude the set before mapping it")))
    }
  }

  /// The verdict of a colour light set, editable: what the pixels said, or what the user asserts.
  @ViewBuilder
  private func filterSet(_ row: ImportPlan.SetRow) -> some View {
    if row.type == .light && row.key.color {
      Picker(
        selection: Binding(
          get: { model.request.filterSets[row.id] ?? row.filterSet },
          set: { model.setFilterSet($0, for: row) })
      ) {
        ForEach(FilterSet.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
      } label: {
        Text(.app("Filter set"))
      }
      .labelsHidden()
      .fixedSize()
      .help(
        model.request.filterSets[row.id] == nil
          ? Text(.app("Measured from the pixels"))
          : Text(.app("Your override; set unknown to measure again")))
    } else {
      Text(verbatim: "—")
    }
  }
}
