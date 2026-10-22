internal import RenderKit
internal import SwiftUI

/// The Stacking panel's settings (card 0070): the simple knobs, the advanced ones behind the
/// disclosure, how many moved from the preset and a way back.
struct KnobPanel: View {
  @Bindable var model: KnobPanelViewModel
  /// A run is going: the values stay in view, frozen (R2); their « ? » stay clickable (R3).
  var frozen = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
        HStack(alignment: .firstTextBaseline) {
          SectionHeader(
            .app("Settings"),
            detail: model.changedCount == 0
              ? .app("The preset, untouched.")
              : .app("\(model.changedCount) changed from the preset"))
          Spacer()
          Button(.app("Reset All")) { model.resetAll() }
            .disabled(model.changedCount == 0 || frozen)
            .accessible(.stackingResetKnobs, label: .app("Reset All"))
        }
        if !model.ignored.isEmpty {
          StatusBadge(
            .attention,
            .app(
              "Not applied, no longer valid settings: \(model.ignored.joined(separator: ", "))"))
        }
        ForEach(model.simpleRows) { KnobRow(row: $0, model: model, frozen: frozen) }
        DisclosureGroup(isExpanded: $model.showsAdvanced) {
          VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
            ForEach(model.advancedRows) { KnobRow(row: $0, model: model, frozen: frozen) }
          }
          .padding(.top, DesignMetrics.spacingS)
        } label: {
          Text(.app("Advanced"))
        }
      }
      .padding(DesignMetrics.spacingM)
    }
  }
}
