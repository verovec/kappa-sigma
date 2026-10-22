internal import RenderKit
internal import SwiftUI

/// The Studio stage: the latest stack's layers and the viewer, read-only until the finishing
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
      HStack(spacing: 0) {
        LayerList(model: studio).frame(width: 260)
        Divider()
        LayerDetail(model: studio)
      }
      .id(studio.source.runID)
    } else {
      EmptyState(
        .app("Studio"),
        message: .app("The stacked image and its finishing processes will appear here."),
        systemImage: "wand.and.stars"
      )
      // Keyed on the choice: picking another stack while this one is empty opens it.
      .task(id: model.selectedStackID) { await model.openStudio() }
    }
  }
}
