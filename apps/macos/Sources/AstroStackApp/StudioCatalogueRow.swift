internal import ProcessKit
internal import RenderKit
package import SwiftUI

/// One process of the Studio's catalogue (card 0087): its rank in the usual order and title, the
/// « usually next » hint (card 0116), and why it is greyed when it cannot be the next step (shown,
/// never hidden: R2).
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
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingXS) {
          if let rank = entry.rank {
            Text(verbatim: AstroFormat(locale: locale).integer(rank))
              .font(.caption).monospacedDigit()
              .foregroundStyle(DesignColor.textSecondary.color)
          }
          Text(title)
        }
        if let stage = nextStage {
          // A suggestion only: nothing greyed, nothing reordered (R2).
          Text(StudioWorkspaceModel.usuallyNextReason(stage))
            .font(.caption).foregroundStyle(DesignColor.statusOK.color)
        }
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

  /// The stage of this process when it is the one usually next, else `nil`.
  private var nextStage: ProcessStage? {
    guard model.usuallyNext == entry.id else { return nil }
    return model.registry.type(id: entry.id)?.stage
  }
}
