internal import ProcessKit
internal import RenderKit
package import SwiftUI

/// One process of the Studio's catalogue (card 0087): its title, and why it is greyed when it
/// cannot be the next step (shown, never hidden: R2).
package struct StudioCatalogueRow: View {
  let entry: StudioWorkspaceModel.Entry
  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale

  /// The row of `entry`, opening its panel in `model` on click.
  package init(entry: StudioWorkspaceModel.Entry, model: StudioWorkspaceModel) {
    self.entry = entry
    self.model = model
  }

  package var body: some View {
    let title = ProcessKitResources.title(entry.title, locale: locale)
    Button {
      model.choose(entry.id)
    } label: {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
        Text(title)
        if let unavailable = entry.unavailable {
          Text(verbatim: StudioCatalogueView.reason(unavailable, locale: locale))
            .font(.caption).foregroundStyle(DesignColor.textSecondary.color)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .opacity(entry.unavailable == nil ? 1 : 0.5)
    .accessible(.studioProcess(entry.id), label: title)
  }
}
