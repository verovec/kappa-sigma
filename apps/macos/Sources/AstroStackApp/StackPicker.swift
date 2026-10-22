internal import RenderKit
internal import SwiftUI

/// Which stack the Studio and the Export stage show (card 0095): the chosen one, newest first in
/// the list.
struct StackPicker: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  var body: some View {
    HStack {
      Picker(
        .app("Stack"),
        selection: Binding(
          get: { model.selectedStack?.id ?? 0 }, set: { model.selectStack($0) })
      ) {
        ForEach(model.stacks.reversed()) { stack in
          Text(verbatim: model.stackLabel(stack, locale: locale)).tag(stack.id)
        }
      }
      .fixedSize()
      .accessible(.studioStack, label: .app("Stack"))
      Spacer()
    }
    .padding(DesignMetrics.spacingM)
  }
}
