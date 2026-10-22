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
}
