internal import ProcessKit
internal import RenderKit
package import SwiftUI

/// The Studio's channel switcher (card 0119): the combined image, then one branch per bundle
/// layer, each with its step count; « Compare with… » another head on the same grid.
package struct StudioChannelSwitcher: View {
  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale

  /// The switcher of `model`.
  package init(model: StudioWorkspaceModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      SectionHeader(
        .app("Channel"), help: StageHelp.help(card: StudioSelection.helpCard, locale: locale))
      ForEach(model.selections, id: \.self) { selection in row(selection) }
      Menu(.app("Compare with…")) {
        Button(.app("No compare")) { compare(nil) }
          .accessible(.studioCompareTarget("none"), label: .app("No compare"))
        ForEach(model.comparable, id: \.self) { other in
          Button {
            compare(other)
          } label: {
            Text(verbatim: StudioSelection.label(other, locale: locale))
          }
          .accessible(
            .studioCompareTarget(other.layerID ?? "main"),
            verbatim: StudioSelection.label(other, locale: locale))
        }
      }
      .disabled(model.comparable.isEmpty)
      .accessible(.studioCompareWith, label: .app("Compare with…"))
    }
    .padding(DesignMetrics.spacingM)
  }

  private func row(_ selection: StudioSelection) -> some View {
    let label = StudioSelection.label(selection, locale: locale)
    let count = model.studio.steps(of: selection).count
    return Button {
      model.select(selection)
    } label: {
      HStack {
        Text(verbatim: label)
        Spacer()
        Text(verbatim: AstroFormat(locale: locale).integer(count))
          .foregroundStyle(DesignColor.textSecondary.color)
        if model.comparingWith == selection { Image(systemName: "rectangle.split.2x1") }
      }
      .fontWeight(model.selection == selection ? .semibold : .regular)
    }
    .buttonStyle(.plain)
    .accessible(.studioChannel(selection.layerID ?? "main"), verbatim: label)
  }

  private func compare(_ other: StudioSelection?) {
    do {
      try model.compare(with: other)
    } catch {
      model.failure = UserFacingError(error).message
    }
  }
}
