internal import RenderKit
internal import StackKit
internal import SwiftUI

/// Every frame of a lane, with its verdict (card 0069).
///
/// Night, metrics in `AstroFormat` units, the verdict as a checkbox while the run waits, and its
/// reason. Sorting a column reorders the blink.
struct FrameTable: View {
  @Bindable var review: FrameReviewViewModel
  @Binding var selection: FrameReviewViewModel.Row.ID?
  @Environment(\.locale) private var locale

  typealias Row = FrameReviewViewModel.Row

  var body: some View {
    Table(review.sortedRows, selection: $selection, sortOrder: $review.sortOrder) {
      TableColumn(Text(.app("#")), value: \Row.index) { row in
        Text(verbatim: format.integer(row.index) + (row.index == review.elected ? " ★" : ""))
          .font(DesignMetrics.valueFont)
      }
      .width(min: 40, ideal: 48)
      TableColumn(Text(.app("Night")), value: \Row.night) { row in
        if row.night.isEmpty { Text(.app("undated")) } else { Text(verbatim: row.night) }
      }
      metrics
      TableColumn(
        Text(review.kind == .reference ? .app("Reference") : .app("Verdict")),
        sortUsing: KeyPathComparator(\Row.keptRank)
      ) { row in
        if review.kind == .reference { reference(row) } else { verdict(row) }
      }
      .width(min: 70, ideal: 80)
      TableColumn(Text(.app("Reason")), value: \Row.reason) { row in
        Text(verbatim: row.reason).foregroundStyle(row.isOverridden ? .primary : .secondary)
      }
    }
    .frame(minHeight: 200)
  }

  /// The registration metrics, each in its unit; an unregistered frame shows none.
  @TableColumnBuilder<Row, KeyPathComparator<Row>>
  private var metrics: some TableColumnContent<Row, KeyPathComparator<Row>> {
    TableColumn(Text(.app("FWHM")), value: \Row.fwhm) { row in
      value(row, format.fwhm(px: row.fwhm))
    }
    TableColumn(Text(.app("Roundness")), value: \Row.roundness) { row in
      value(row, format.decimal(row.roundness, maxFractionDigits: 2, minFractionDigits: 2))
    }
    TableColumn(Text(.app("Stars")), value: \Row.starCount) { row in
      value(row, format.integer(row.starCount))
    }
    TableColumn(Text(.app("Background")), value: \Row.background) { row in
      value(row, format.significant(row.background, digits: 3))
    }
    TableColumn(Text(.app("Trail")), value: \Row.trailScore) { row in
      value(row, row.trailDetected ? format.significant(row.trailScore, digits: 2) : "")
    }
    TableColumn(Text(.app("Shift")), value: \Row.shift) { row in
      value(row, format.fwhm(px: row.shift))
    }
    if review.kind == .reference {
      // The reference fixes the orientation: say which nights were mirrored to the convention.
      TableColumn(Text(.app("Parity")), value: \Row.parityRank) { row in
        if row.parity == .mirrored { Text(.app("mirrored")) } else { Text(verbatim: "") }
      }
    }
  }

  /// A metric; an unregistered frame has none.
  private func value(_ row: Row, _ text: String) -> some View {
    Text(verbatim: row.isRegistered ? text : "—").font(DesignMetrics.valueFont)
  }

  /// The reference radio at a reference pause (card 0096): one frame per lane, the elected one
  /// marked until changed; a dropped frame cannot be chosen.
  @ViewBuilder private func reference(_ row: Row) -> some View {
    let chosen = review.isReference(row)
    if review.isLive && row.isRegistered {
      Button {
        review.setReference(row.index)
      } label: {
        Label {
          Text(row.index == review.elected ? .app("elected") : .app("reference"))
        } icon: {
          if chosen {
            Image(systemName: "largecircle.fill.circle")
          } else {
            Image(systemName: "circle")
          }
        }
      }
      .buttonStyle(.borderless)
      .accessibilityAddTraits(chosen ? [.isSelected] : [])
      .accessible(
        .reviewReference(row.index),
        label: .app("Make frame \(format.integer(row.index)) the reference"))
    } else if chosen {
      StatusBadge(.ok, .app("reference"))
    } else {
      Text(verbatim: "")
    }
  }

  /// Keep / reject, editable while the run waits; the verdict words otherwise.
  @ViewBuilder private func verdict(_ row: Row) -> some View {
    if review.isLive && row.isRegistered {
      Toggle(isOn: Binding(get: { row.isKept }, set: { _ in review.toggle(row.index) })) {
        Text(row.isKept ? .app("Keep") : .app("Reject"))
      }
      .toggleStyle(.checkbox)
      .accessible(.reviewKeep(row.index), label: .app("Keep frame \(format.integer(row.index))"))
    } else if row.isKept {
      StatusBadge(.ok, .app("Keep"))
    } else {
      StatusBadge(.unavailable, .app("Reject"))
    }
  }

  private var format: AstroFormat { AstroFormat(locale: locale) }
}

extension FrameReviewViewModel.Row {
  /// The verdict as a sort key: rejected frames first.
  nonisolated var keptRank: Int { isKept ? 1 : 0 }

  /// The parity as a sort key: mirrored nights first, unprobed last.
  nonisolated var parityRank: Int {
    switch parity {
    case .mirrored: 0
    case .same: 1
    case .unprobed: 2
    }
  }
}
