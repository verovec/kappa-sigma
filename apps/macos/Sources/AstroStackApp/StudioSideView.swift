internal import ProcessKit
internal import RenderKit
package import SwiftUI

/// The Studio's right column (card 0087): the chosen process's panel with Apply, then the
/// history — each step comparable, Undo and Redo.
package struct StudioSideView: View {
  let model: StudioWorkspaceModel
  @Environment(\.undoManager) private var undoManager
  @Environment(\.locale) private var locale

  /// The side column of `model`.
  package init(model: StudioWorkspaceModel) {
    self.model = model
  }

  package var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
        if let panel = model.panel {
          ProcessPanel(model: panel)
          StudioMaskRow(model: model)
          HStack {
            Button(.app("Close")) { model.closePanel() }
              .accessible(.studioClosePanel, label: .app("Close"))
            Spacer()
            // No default-button Return: Return confirms a typed value (Edit › Apply Process ⌘E).
            Button(.app("Apply")) { applyRecorded() }
              .accessible(.studioApply, label: .app("Apply"))
          }
        } else {
          Text(.app("Choose a process in the catalogue."))
            .foregroundStyle(DesignColor.textSecondary.color)
        }
        if let failure = model.failure { StatusBadge(.error, failure) }
        history
      }
      .padding(DesignMetrics.spacingM)
    }
  }

  private var history: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      HStack {
        SectionHeader(.app("History"))
        Spacer()
        Button(.app("Undo")) { undo() }
          .disabled(!model.studio.canUndo)
          .accessible(.studioUndo, label: .app("Undo"))
        Button(.app("Redo")) { redo() }
          .disabled(!model.studio.canRedo)
          .accessible(.studioRedo, label: .app("Redo"))
      }
      ForEach(Array(model.studio.steps.enumerated()), id: \.offset) { index, step in
        // A host-tool step has no ProcessKit title: its own, in the view's language.
        let title =
          StarSeparation.title(of: step.processID, locale: locale)
          ?? ProcessKitResources.title(model.title(of: step.processID), locale: locale)
        Button {
          model.toggleCompare(index)
        } label: {
          HStack {
            Text(verbatim: "\(index + 1).")
            Text(title)
            Spacer()
            if model.comparing == index { Image(systemName: "rectangle.split.2x1") }
          }
        }
        .buttonStyle(.plain)
        .accessible(.studioStep(index), label: title)
      }
    }
  }

  /// Applies the panel and records the step with the window's undo manager, so ⌘Z / ⇧⌘Z reach
  /// the history too.
  private func applyRecorded() {
    StudioUndo.apply(model, undoManager: undoManager)
  }

  /// One step back on the history itself (the window's undo manager may hold unrelated typing
  /// on top; ⌘Z reaches the Studio's own registered moves).
  private func undo() {
    try? model.undo()
  }

  private func redo() {
    try? model.redo()
  }
}
