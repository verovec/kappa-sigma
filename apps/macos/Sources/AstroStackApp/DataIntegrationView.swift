internal import RenderKit
internal import StackKit
internal import SwiftUI

/// What the capture holds (0078): the totals, then the lights per filter × night.
struct DataIntegrationView: View {
  var summary: IntegrationSummary
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      HStack(spacing: DesignMetrics.spacingXL) {
        MetricValue(
          .app("Integration"), value: format.integration(seconds: summary.integrationMs / 1000))
        MetricValue(.app("Lights"), value: format.integer(summary.frames))
        MetricValue(.app("Nights"), value: format.integer(summary.nights))
      }
      Grid(alignment: .leading, horizontalSpacing: DesignMetrics.spacingL, verticalSpacing: 6) {
        columns
        Divider()
        ForEach(summary.rows) { row in gridRow(row) }
      }
    }
  }

  private var columns: some View {
    GridRow {
      Text(.app("Filter"))
      Text(.app("Night"))
      Text(.app("Lights"))
      Text(.app("Exposure"))
      Text(.app("Integration"))
      Text(.app("Sensor"))
    }
    .font(.caption)
    .foregroundStyle(DesignColor.textSecondary.color)
  }

  private func gridRow(_ row: IntegrationSummary.Row) -> some View {
    GridRow {
      Text(verbatim: ImportFormat.filter(row.filter, filterSet: row.filterSet, locale: locale))
      if row.night.isEmpty { Text(.app("undated")) } else { Text(verbatim: row.night) }
      Text(verbatim: format.integer(row.frames))
      Text(verbatim: row.exposuresMs.map { format.exposure(ms: $0) }.joined(separator: ", "))
      Text(verbatim: format.integration(seconds: row.integrationMs / 1000))
      Text(verbatim: temperature(row.temperatureC))
    }
    .font(DesignMetrics.valueFont)
  }

  private var format: AstroFormat { AstroFormat(locale: locale) }

  /// The sensor's range over the row, whole °C (`−10 °C`, `−12 °C … −9 °C`); `—` when unrecorded.
  private func temperature(_ range: ClosedRange<Double>?) -> String {
    guard let range else { return "—" }
    let (low, high) = (Int(range.lowerBound.rounded()), Int(range.upperBound.rounded()))
    return low == high
      ? format.temperature(celsius: low)
      : format.temperature(celsius: low) + " … " + format.temperature(celsius: high)
  }
}
