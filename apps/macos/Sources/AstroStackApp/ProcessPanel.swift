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
      if let solved = model.solved {
        Text(verbatim: ProcessPanelModel.solvedWords(solved, locale: locale))
          .font(.caption).foregroundStyle(.secondary)
      }
      if let sample = model.sample {
        ProcessHistogramExtras(model: model, sample: sample)
      }
      takeTogether
      if !model.paletteOptions.isEmpty {
        paletteMenu
      }
      ForEach(model.visibleSpecs, id: \.id) { spec in
        ProcessParameterRow(spec: spec, model: model)
      }
      if model.hasAdvanced {
        Toggle(isOn: $model.showsAdvanced) { Text(.app("Advanced")) }
          .toggleStyle(.switch)
          .accessible(.processAdvanced(model.type.id), label: .app("Advanced"))
      }
    }
  }

  /// The palettes the stack offers (card 0139): a template that fills the sources on screen;
  /// « Custom » names any other combination, and a kept palette the stack lacks stays named.
  private var paletteMenu: some View {
    let kept = model.palette.map { model.paletteOptions.contains($0) ? [] : [$0] } ?? []
    return Picker(selection: paletteSelection) {
      ForEach(model.paletteOptions + kept, id: \.self) { palette in
        Text(ProcessKitResources.title(palette.title, locale: locale)).tag(palette.rawValue)
      }
      Text(.app("Custom")).tag("custom")
    } label: {
      Text(.app("Palette"))
    }
    .accessible(.parameter("\(model.type.id).palette", .choice), label: .app("Palette"))
  }

  private var paletteSelection: Binding<String> {
    Binding(
      get: { model.palette?.rawValue ?? "custom" },
      set: { raw in
        if let palette = Palette(rawValue: raw) { model.choose(palette: palette) }
      })
  }

  /// One button per reason several suggestions share: one click takes them all.
  private var takeTogether: some View {
    ForEach(Array(model.groupedReasons.enumerated()), id: \.offset) { offset, reason in
      Button {
        model.take(reason: reason)
      } label: {
        let words = ProcessPanelModel.words(
          reason: reason, subject: model.subject(of: reason), locale: locale)
        Text(.app("Take together: \(words)"))
      }
      .accessible(.suggestion(model.togetherKey, offset), label: .app("Take together"))
    }
  }
}
