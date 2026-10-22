internal import ProjectKit
internal import RenderKit
package import SwiftUI

/// « Replay pipeline on… » (card 0088): the project's other stacks, as the stack picker names
/// them; choosing one switches the Studio to it and runs the pipeline there.
package struct ReplayChooser: View {
  let model: ProjectWindowModel
  @Environment(\.locale) private var locale

  /// The chooser of the window `model`.
  package init(model: ProjectWindowModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      Text(.app("Replay the pipeline on")).font(.headline)
      ForEach(model.replayTargets) { stack in
        Button {
          model.isChoosingReplay = false
          model.replayPipeline(on: stack.id)
        } label: {
          Text(verbatim: model.stackLabel(stack, locale: locale))
        }
        .accessible(.studioPipelineReplayTarget(stack.id), label: .app("Replay the pipeline on"))
      }
      HStack {
        Spacer()
        Button(.app("Cancel")) { model.isChoosingReplay = false }
          .keyboardShortcut(.cancelAction)
          .accessible(.studioPipelineReplayCancel, label: .app("Cancel"))
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(minWidth: 360)
  }
}
