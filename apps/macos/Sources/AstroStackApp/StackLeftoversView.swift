internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The stack folders a run left without a stack (card 0113), each with its size and Delete:
/// finished masters are kept until the user deletes them, never in silence (R2).
struct StackLeftoversView: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale
  @State private var confirming: LeftoverStack?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      ForEach(model.leftoverStacks, id: \.path) { leftover in
        HStack(alignment: .firstTextBaseline) {
          Label {
            Text(notice(leftover))
          } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
          }
          .foregroundStyle(DesignColor.statusAttention.color)
          Spacer()
          Button(.app("Delete…"), role: .destructive) { confirming = leftover }
            .accessible(.stackingDeleteLeftover(name(leftover)), label: .app("Delete…"))
        }
      }
    }
    .padding([.horizontal, .bottom], DesignMetrics.spacingM)
    .confirmationDialog(
      Text(.app("Delete \(confirming?.path ?? "")?")),
      isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
      presenting: confirming
    ) { leftover in
      Button(.app("Delete"), role: .destructive) { model.deleteLeftoverStack(leftover) }
      Button(.app("Cancel"), role: .cancel) {}
    } message: { leftover in
      Text(
        .app(
          "Its \(size(leftover)) of masters and previews leave the project; this cannot be undone.")
      )
    }
  }

  private func notice(_ leftover: LeftoverStack) -> LocalizedStringResource {
    .app("\(leftover.path) — \(size(leftover)) kept: no stack records it (an unfinished run).")
  }

  private func size(_ leftover: LeftoverStack) -> String {
    AstroFormat(locale: locale).bytes(leftover.bytes)
  }

  private func name(_ leftover: LeftoverStack) -> String {
    String(leftover.path.split(separator: "/").last ?? "")
  }
}
