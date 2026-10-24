internal import HelpKit
internal import ProcessKit
internal import RenderKit
package import SwiftUI

/// The panel of one process, generated from its schema (card 0087): the card on top, one row
/// per parameter (number, flag, choice, curve), the advanced ones behind the disclosure, the
/// suggestions as buttons that set a value only when clicked.
package struct ProcessPanel: View {
  @Bindable var model: ProcessPanelModel
  @Environment(\.locale) private var locale

  /// The panel of `model`.
  package init(model: ProcessPanelModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      if let card = model.card(locale: locale) {
        DisclosureGroup {
          HelpText(card)
        } label: {
          Text(ProcessKitResources.title(model.type.title, locale: locale))
            .font(.headline)
        }
      }
      if !model.shownMaxima.isEmpty { shownMaximaLine }
      if let sample = model.sample {
        ProcessHistogramExtras(model: model, sample: sample)
      }
      ForEach(Array(model.groupedReasons.enumerated()), id: \.offset) { offset, reason in
        Button {
          model.take(reason: reason)
        } label: {
          let words = String(localized: ProcessKitResources.title(reason, locale: locale))
          Text(.app("Take together: \(words)"))
        }
        .accessible(.suggestion(model.togetherKey, offset), label: .app("Take together"))
      }
      ForEach(model.visibleSpecs, id: \.id) { spec in
        ProcessParameterRow(spec: spec, model: model)
      }
      if model.type.schema.hasAdvanced {
        Toggle(isOn: $model.showsAdvanced) { Text(.app("Advanced")) }
          .toggleStyle(.switch)
          .accessible(.processAdvanced(model.type.id), label: .app("Advanced"))
      }
    }
  }

  /// The maximum per channel of the image on screen (a `RangeShown` process clips nothing).
  private var shownMaximaLine: some View {
    let format = AstroFormat(locale: locale)
    let values = model.shownMaxima.map { words($0, format) }.joined(
      separator: " · ")
    return Text(.app("Maximum on screen: \(values)"))
      .font(.caption)
      .monospacedDigit()
  }

  /// A channel's maximum: « ∞ » for a saturated (infinite) one, « — » when every value is NaN.
  private func words(_ maximum: Double, _ format: AstroFormat) -> String {
    if maximum == .infinity { return "∞" }
    return maximum.isFinite ? format.parameter(maximum) : "—"
  }
}
