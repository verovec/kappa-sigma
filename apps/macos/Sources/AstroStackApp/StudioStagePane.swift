internal import RenderKit
internal import SwiftUI

/// The Studio stage: the chosen stack's layers and the viewer, read-only until the finishing
/// processes (E12) land here.
struct StudioStagePane: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(spacing: 0) {
      if model.stacks.count > 1 { picker }
      content
    }
  }

  /// Which stack the Studio shows (card 0095): the chosen one, newest first in the list.
  private var picker: some View {
    HStack {
      Picker(
        .app("Stack"),
        selection: Binding(
          get: { model.selectedStack?.id ?? 0 }, set: { model.selectStack($0) })
      ) {
        ForEach(model.stacks.reversed()) { stack in
          Text(
            verbatim: model.stackLabel(stack, locale: locale)
          )
          .tag(stack.id)
        }
      }
      .fixedSize()
      .accessible(.studioStack, label: .app("Stack"))
      Spacer()
    }
    .padding(DesignMetrics.spacingM)
  }

  @ViewBuilder private var content: some View {
    if let studio = model.studio {
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
