internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The series the next run stacks (card 0095): the last scan's light sets, object → night, a
/// checkbox each; one run per object with a checked set, named on the Run button.
struct StackingSeriesView: View {
  @Bindable var model: StackingStageModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      SectionHeader(.app("Series"), detail: detail)
      if model.isEmpty {
        Text(
          .app(
            "Rescan (Données › Rescan) to list the series; until then a run stacks every light."
          )
        )
        .font(.caption)
        .foregroundStyle(DesignColor.textSecondary.color)
      } else {
        ForEach(model.groups) { group in
          if model.groups.count > 1 {
            if group.object.isEmpty {
              Text(.app("Unnamed object")).font(.headline)
            } else {
              Text(verbatim: group.object).font(.headline)
            }
          }
          ForEach(group.nights) { night in
            if !night.night.isEmpty {
              Text(ImportFormat.night(night.night))
                .font(.caption)
                .foregroundStyle(DesignColor.textSecondary.color)
            }
            ForEach(night.series) { series in row(series) }
          }
        }
      }
    }
  }

  private var detail: LocalizedStringResource {
    let runs = model.scopes.count
    return runs > 1 ? .app("\(runs) objects, one run each.") : .app("One run of every checked set.")
  }

  private func row(_ series: StackingStageModel.Series) -> some View {
    Toggle(
      isOn: Binding(
        get: { model.isChecked(series.id) }, set: { model.set(series.id, checked: $0) })
    ) {
      Text(verbatim: words(series))
        .font(DesignMetrics.valueFont)
    }
    .accessible(.stackingSeries(series.id), verbatim: words(series))
  }

  /// « L · 120 s · g100 · 36 lights · 1 h 12 min » (the gain as masters name it).
  private func words(_ series: StackingStageModel.Series) -> String {
    let format = AstroFormat(locale: locale)
    return [
      ImportFormat.filter(series.filter, filterSet: series.filterSet, locale: locale),
      format.exposure(ms: series.exposureMs),
      String(localized: .app("g\(series.gain)", locale: locale)),
      format.lights(series.frames),
      format.integration(seconds: Int((Double(series.integrationMs) / 1000).rounded())),
    ].joined(separator: " · ")
  }
}
