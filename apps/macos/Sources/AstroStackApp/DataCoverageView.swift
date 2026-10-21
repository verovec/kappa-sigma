internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The calibration coverage of each light set (0078).
///
/// Dark, flat and bias as the matcher decided them, with its notes verbatim; the Calibration
/// stage shows each master in full, one click away.
struct DataCoverageView: View {
  var coverage: CoverageMatrix
  var openCalibration: () -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      HStack(alignment: .firstTextBaseline) {
        SectionHeader(.app("Calibration coverage"), detail: .app("The matcher's choice, as is."))
        Spacer()
        Button(.app("Open Calibration")) { openCalibration() }
          .accessible(.dataOpenCalibration, label: .app("Open Calibration"))
      }
      Grid(alignment: .leading, horizontalSpacing: DesignMetrics.spacingL, verticalSpacing: 6) {
        columns
        Divider()
        ForEach(coverage.rows) { row in rows(row) }
      }
    }
  }

  private var columns: some View {
    GridRow {
      Text(.app("Light set"))
      ForEach(CalibrationRole.allCases, id: \.self) { role in
        Text(verbatim: AppGlossary.label(role.frameType.termID, locale: locale))
      }
    }
    .font(.caption)
    .foregroundStyle(DesignColor.textSecondary.color)
  }

  /// A light set's badges, then StackKit's matcher notes, as it words them.
  @ViewBuilder private func rows(_ row: CoverageMatrix.Row) -> some View {
    GridRow {
      Text(verbatim: coverage.heading(row, locale: locale))
      ForEach(row.cells) { cell in
        StatusBadge(ImportFormat.badge(cell.status), ImportFormat.status(cell.status))
      }
    }
    // By position: the matcher may word two notes alike.
    ForEach(Array(row.notes.enumerated()), id: \.offset) { _, note in
      GridRow {
        Label(note, systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(DesignColor.textSecondary.color)
          .gridCellColumns(CalibrationRole.allCases.count + 1)
      }
    }
  }
}
