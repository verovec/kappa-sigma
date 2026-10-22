internal import ProcessKit
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The rows under a batch process's panel (card 0092): the install card of a missing engine
/// tool (its option is greyed, Apply refused with the reason), the tool's progress while it
/// runs, and the toggle that shows the background model in the viewer.
struct StudioBatchRows: View {
  let model: StudioWorkspaceModel
  @State private var card: InstallCardModel?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      if let missing = model.missingTool, let card {
        InstallCard(
          tool: missing.tool.productName,
          reason: StudioWorkspaceModel.reason(missing.tool, missing.status)
            ?? .app("Extracts the background and denoises."),
          installURL: missing.tool.installURL, model: card)
      }
      if let progress = model.batchProgress {
        ProgressView(value: progress) { Text(.app("Running the tool…")) }
          .accessible(.studioBatchProgress, label: .app("Running the tool…"))
      }
      Toggle(
        isOn: Binding(get: { model.showsModel }, set: { _ in try? model.toggleModel() })
      ) { Text(.app("Show the background model")) }
      .toggleStyle(.switch)
      .disabled(!model.canShowModel)
      .accessible(.studioShowModel, label: .app("Show the background model"))
    }
    .task(id: model.missingTool?.tool) { makeCard() }
    // A tool found by « Re-check » makes its option available again.
    .onChange(of: card?.state) { _, state in
      if case .found = state { Task { await model.refreshTools() } }
    }
  }

  private func makeCard() {
    guard let missing = model.missingTool else {
      card = nil
      return
    }
    let (tool, locate) = (missing.tool, model.tools.locate)
    card = InstallCardModel(state: WelcomeModel.cardState(missing.status)) { @concurrent in
      WelcomeModel.cardState(await locate(tool))
    }
  }
}
