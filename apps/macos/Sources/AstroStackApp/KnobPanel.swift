internal import RenderKit
internal import SwiftUI

/// The Stacking panel's settings (card 0070): the simple knobs, the advanced ones behind the
/// disclosure, how many moved from the preset and a way back.
struct KnobPanel: View {
  @Bindable var model: KnobPanelViewModel

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
            .disabled(model.changedCount == 0)
        }
        ForEach(model.rows.filter { $0.level == .simple }) { KnobRow(row: $0, model: model) }
        DisclosureGroup(isExpanded: $model.showsAdvanced) {
          VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
            ForEach(model.rows.filter { $0.level == .advanced }) { KnobRow(row: $0, model: model) }
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
