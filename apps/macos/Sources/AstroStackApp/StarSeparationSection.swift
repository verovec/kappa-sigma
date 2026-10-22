internal import RenderKit
internal import StackKit
internal import SwiftUI

/// Where the starless comes from: the state of the head's starless, « Separate stars », and
/// StarNet's install card when this Mac has none it can run.
struct StarSeparationSection: View {
  var model: ExportStageModel

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      Text(.app("Stars")).font(.headline)
      if model.hasStarless {
        StatusBadge(.ok, .app("Starless ready: the star blends can be written."))
        if model.stepsAfterStarless > 0 {
          Text(.app("\(model.stepsAfterStarless) steps came after it: separate again to match."))
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Text(.app("Without a starless, only the final image is written."))
          .font(.caption).foregroundStyle(.secondary)
      }
      StarSeparationButton(model: model)
      if let card = model.installCard {
        InstallCard(
          tool: HostTool.starnet.productName,
          reason: model.installReason ?? .app("Separates the stars from the nebula."),
          installURL: HostTool.starnet.installURL, model: card)
      }
    }
  }
}
