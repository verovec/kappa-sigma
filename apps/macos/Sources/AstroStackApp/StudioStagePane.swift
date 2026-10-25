internal import RenderKit
internal import SwiftUI

/// The Studio stage: the chosen stack's workspace (catalogue, working image, panel, history —
/// card 0087), its read-only layers while the workspace loads.
struct StudioStagePane: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(spacing: 0) {
      // The full-screen image (card 0127) shows nothing but the image.
      if model.stacks.count > 1, model.workspace?.isFocused != true { picker }
      content
    }
    .sheet(
      isPresented: Binding(
        get: { model.isChoosingReplay }, set: { model.isChoosingReplay = $0 })
    ) {
      ReplayChooser(model: model)
    }
  }

  /// Which stack the Studio shows (card 0095): the chosen one, newest first in the list.
  private var picker: some View {
    StackPicker(model: model)
  }

  /// The stage's title, with StarNet offered where its starless is used.
  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      SectionHeader(.app("Studio"), help: StageHelp.help(.studio, locale: locale))
      Spacer()
      // Star recomposition reads StarNet's starless: separating is offered where it is used.
      if let export = model.exportStage, !export.hasStarless {
        StarSeparationButton(model: export) { model.separateStarsFromStudio() }
      }
    }
    .padding(DesignMetrics.spacingM)
  }

  @ViewBuilder private var content: some View {
    if let workspace = model.workspace {
      VStack(alignment: .leading, spacing: 0) {
        if !workspace.isFocused { header }
        StudioWorkspaceView(model: workspace)
      }
    } else if let studio = model.studio {
      VStack(alignment: .leading, spacing: 0) {
        SectionHeader(.app("Studio"), help: StageHelp.help(.studio, locale: locale))
          .padding(DesignMetrics.spacingM)
        HStack(spacing: 0) {
          LayerList(model: studio).frame(width: 260)
          Divider()
          LayerDetail(model: studio)
        }
        .id(studio.source.runID)
      }
      // The workspace of the shown stack failed or is loading: coming back retries it.
      .task(id: model.selectedStack?.id) { model.retryWorkspace() }
    } else {
      EmptyState(
        .app("Studio"),
        message: .app("The stacked image and its finishing processes will appear here."),
        systemImage: "wand.and.stars", help: StageHelp.help(.studio, locale: locale)
      )
      // Keyed on the stack to show: another pick, or a new latest, opens it while this is empty.
      .task(id: model.selectedStack?.id) { await model.openStudio() }
    }
  }
}
