internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The calibration coverage of each light set (0078).
///
/// Dark, flat and bias as the matcher decided them, with its notes verbatim. Changing a choice is
/// the Calibration stage's, one click away.
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
      Text(verbatim: heading(row))
      ForEach(row.cells) { cell in
        StatusBadge(ImportFormat.badge(cell.status), ImportFormat.status(cell.status))
      }
    }
    ForEach(row.notes, id: \.self) { note in
      GridRow {
        Label(note, systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(DesignColor.textSecondary.color)
          .gridCellColumns(CalibrationRole.allCases.count + 1)
      }
    }
  }

  /// « RGB · dual-band · 300 s · 2026-09-22 ».
  private func heading(_ row: CoverageMatrix.Row) -> String {
    let format = AstroFormat(locale: locale)
    let parts =
      [
        ImportFormat.filter(row.channel.filter, filterSet: row.filterSet, locale: locale),
        format.exposure(ms: row.channel.key.exposureMs),
      ] + (row.night.isEmpty ? [] : [row.night])
    return parts.joined(separator: " · ")
  }
}
