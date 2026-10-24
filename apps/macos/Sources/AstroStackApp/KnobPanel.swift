internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Stacking panel's settings (card 0070): the simple knobs, the advanced ones behind the
/// disclosure, how many moved from the preset and a way back.
///
/// When the checked series split into broadband and dual-band lanes (card 0121): what follows the
/// stack, and the values of each lane.
struct KnobPanel: View {
  @Bindable var model: KnobPanelViewModel
  /// The lane columns of the checked series: none unless they split.
  var lanes: [FilterSet] = []
  /// A run is going: the values stay in view, frozen (R2); their « ? » stay clickable (R3).
  var frozen = false
  /// The lane whose values the rows show and edit; nil: the global values.
  @State private var lane: FilterSet?
  @Environment(\.locale) private var locale

  /// The lane shown, while the series still split.
  private var shownLane: FilterSet? { lane.flatMap { lanes.contains($0) ? $0 : nil } }

  var body: some View {
    let rows = shownLane.map { model.rows(lane: $0) } ?? model.rows
    // The Stacking pane scrolls the series and the knobs together (0095): no scroller here.
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      header
      if !lanes.isEmpty { laneSection }
      ForEach(rows.filter { $0.level == .simple }) {
        KnobRow(row: $0, model: model, lane: shownLane, frozen: frozen)
      }
      DisclosureGroup(isExpanded: $model.showsAdvanced) {
        VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
          ForEach(rows.filter { $0.level == .advanced }) {
            KnobRow(row: $0, model: model, lane: shownLane, frozen: frozen)
          }
        }
        .padding(.top, DesignMetrics.spacingS)
      } label: {
        Text(.app("Advanced"))
      }
    }
    .padding(DesignMetrics.spacingM)
  }

  /// The section's title, how many knobs moved, Reset All, and the record's refused values.
  @ViewBuilder private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      SectionHeader(
        .app("Settings"),
        detail: model.changedCount == 0
          ? .app("The preset, untouched.")
          : .app("\(model.changedCount) changed from the preset"))
      Spacer()
      Button(.app("Reset All")) { model.resetAll() }
        .disabled((model.changedCount == 0 && model.lanesUntouched) || frozen)
        .accessible(.stackingResetKnobs, label: .app("Reset All"))
    }
    if !model.ignored.isEmpty {
      StatusBadge(
        .attention,
        .app(
          "Not applied, no longer valid settings: \(model.ignored.joined(separator: ", "))"))
    }
  }

  /// What follows the stack, then which lane the rows show — every lane's overrides counted, so
  /// no value applied is out of sight (R2).
  private var laneSection: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      Picker(.app("After stacking"), selection: $model.processing) {
        Text(.app("One flow")).tag(StackProcessing.single)
        Text(.app("Per channel")).tag(StackProcessing.perChannel)
      }
      .pickerStyle(.radioGroup)
      .disabled(frozen)
      .accessible(.stackingProcessing, label: .app("After stacking"))
      Text(
        .app(
          "Broadband, Hα and OIII processed apart, then combined; the stack is the same."
        )
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Picker(.app("Values for"), selection: $lane) {
        Text(.app("Every lane")).tag(FilterSet?.none)
        ForEach(lanes, id: \.self) { lane in
          Text(verbatim: laneLabel(lane)).tag(Optional(lane))
        }
      }
      .pickerStyle(.segmented)
      .accessible(.stackingLane, label: .app("Values for"))
      ForEach(lanes.filter { model.overrideCount(lane: $0) > 0 }, id: \.self) { lane in
        StatusBadge(
          .attention,
          .app(
            "\(laneLabel(lane)): \(model.overrideCount(lane: lane)) changed from the global values")
        )
      }
    }
  }

  /// The lane's glossary label: « Large bande », « Bi-bande ».
  private func laneLabel(_ lane: FilterSet) -> String {
    AppGlossary.label(lane.termID, locale: locale)
  }
}
