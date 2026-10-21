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
          .app("Integration"), value: integration(summary.integrationMs))
        MetricValue(.app("Lights"), value: format.integer(summary.frames))
        MetricValue(.app("Nights"), value: format.integer(summary.nights))
      }
      Grid(alignment: .leading, horizontalSpacing: DesignMetrics.spacingL, verticalSpacing: 6) {
        columns
        Divider()
        ForEach(summary.rows) { row in gridRow(row) }
        if summary.rows.count > summary.totals.count {
          Divider()
          ForEach(summary.totals) { total in totalRow(total) }
        }
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

  /// A filter over every night, shown once a filter spans several rows.
  private func totalRow(_ total: IntegrationSummary.Total) -> some View {
    GridRow {
      Text(verbatim: filter(total.object, total.filter, total.filterSet))
      Text(.app("total"))
      Text(verbatim: format.integer(total.frames))
      Text(verbatim: "")
      Text(verbatim: integration(total.integrationMs))
      Text(verbatim: "")
    }
    .font(DesignMetrics.valueFont.weight(.semibold))
  }

  private func gridRow(_ row: IntegrationSummary.Row) -> some View {
    GridRow {
      Text(verbatim: filter(row.object, row.filter, row.filterSet))
      if row.night.isEmpty { Text(.app("undated")) } else { Text(verbatim: row.night) }
      Text(verbatim: format.integer(row.frames))
      Text(verbatim: row.exposuresMs.map { format.exposure(ms: $0) }.joined(separator: ", "))
      Text(verbatim: integration(row.integrationMs))
      Text(verbatim: temperature(row.temperatureC))
    }
    .font(DesignMetrics.valueFont)
  }

  private var format: AstroFormat { AstroFormat(locale: locale) }

  /// Rounded to the second, never truncated: sub-second exposures still add up.
  private func integration(_ milliseconds: Int) -> String {
    format.integration(seconds: Int((Double(milliseconds) / 1000).rounded()))
  }

  /// The filter in words, after its target when the capture holds several.
  private func filter(_ object: String, _ filter: String, _ filterSet: FilterSet) -> String {
    let words = ImportFormat.filter(filter, filterSet: filterSet, locale: locale)
    return summary.targets > 1 && !object.isEmpty ? object + " · " + words : words
  }

  /// The sensor's range over the row, whole °C (`−10 °C`, `−12 °C … −9 °C`); `—` when unrecorded.
  private func temperature(_ range: ClosedRange<Double>?) -> String {
    guard let range else { return "—" }
    let (low, high) = (Int(range.lowerBound.rounded()), Int(range.upperBound.rounded()))
    return low == high
      ? format.temperature(celsius: low)
      : format.temperature(celsius: low) + " … " + format.temperature(celsius: high)
  }
}
