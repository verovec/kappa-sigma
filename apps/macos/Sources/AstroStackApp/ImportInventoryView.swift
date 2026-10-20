internal import StackKit
internal import SwiftUI

/// The scan, night by night: one row per frame set, with its overrides beside it.
struct ImportInventoryView: View {
  var model: ImportViewModel
  var plan: ImportPlan

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(plan.nights) { night in
        GroupBox(ImportFormat.night(night.session)) {
          Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
              ForEach(Self.columns, id: \.self) {
                Text($0).font(.caption).foregroundStyle(.secondary)
              }
            }
            ForEach(night.sets) { row in setRow(row) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  static let columns = [
    "Type", "Object", "Filter", "Exposure", "Sensor", "Temp.", "Frames", "Filter set", "",
  ]

  private func setRow(_ row: ImportPlan.SetRow) -> some View {
    GridRow {
      Text(row.type.rawValue)
      Text(row.key.object.isEmpty ? "—" : row.key.object)
      Text(row.filter.isEmpty ? "—" : row.filter)
      Text(ImportFormat.exposure(row.key.exposureMs)).monospacedDigit()
      Text(ImportFormat.sensor(row.key)).monospacedDigit()
      Text(ImportFormat.temperature(row.key)).monospacedDigit()
      Text("\(row.count)").monospacedDigit()
      filterSet(row)
      Button("Exclude") { model.exclude(row) }
        .disabled(!model.canExclude(row))
        .help(
          model.canExclude(row)
            ? "Drop every frame of this set from the stack"
            : "This filter may come from the filter map: exclude the set before mapping it")
    }
  }

  /// The verdict of a colour light set, editable: what the pixels said, or what the user asserts.
  @ViewBuilder
  private func filterSet(_ row: ImportPlan.SetRow) -> some View {
    if row.type == .light && row.key.color {
      Picker(
        "Filter set",
        selection: Binding(
          get: { model.request.filterSets[row.id] ?? row.filterSet },
          set: { model.setFilterSet($0, for: row) })
      ) {
        ForEach(FilterSet.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .labelsHidden()
      .fixedSize()
      .help(
        model.request.filterSets[row.id] == nil
          ? "Measured from the pixels" : "Your override; set unknown to measure again")
    } else {
      Text("—")
    }
  }
}
