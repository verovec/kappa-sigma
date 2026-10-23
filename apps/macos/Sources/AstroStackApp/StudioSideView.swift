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
          rows(under: panel)
          HStack {
            Button(.app("Close")) { model.closePanel() }
              .accessible(.studioClosePanel, label: .app("Close"))
            Spacer()
            // No default-button Return: Return confirms a typed value (Edit › Apply Process ⌘E).
            // On a new head Apply previews first, and says so.
            Button(model.isPreviewSuspended ? .app("Preview") : .app("Apply")) { applyRecorded() }
              .disabled(model.toolRun != nil)
              .accessible(.studioApply, label: .app("Apply"))
          }
          StudioToolRow(model: model)
          if model.isPreviewSuspended { suspended }
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

  /// What the panel's process asks for below its parameters: the mask row, or its own rows.
  @ViewBuilder
  private func rows(under panel: ProcessPanelModel) -> some View {
    if panel.type is any GeometricProcess.Type {
      // Geometry moves the whole grid: no mask, the output's size and solution instead
      // (none while the values leave no pixel: the panel shows that failure).
      if let output = model.geometryOutput { GeometryExtras(model: model, output: output) }
    } else if panel.type.id == BackgroundExtractionProcess.id {
      // The extraction runs on the whole image and its layers: no mask, its own rows.
      StudioBatchRows(model: model)
    } else {
      StudioMaskRow(model: model)
    }
  }

  /// The history moved under the panel: the viewer shows the image, not these values.
  private var suspended: some View {
    StatusBadge(
      .attention, .app("The image is shown as applied: Preview shows these values on it."))
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
        stepRow(index, step)
      }
    }
  }

  /// One applied step: its number and title, a click compares the viewer with its output.
  private func stepRow(_ index: Int, _ step: History.Step) -> some View {
    // A host-tool step has no ProcessKit title: its own, in the view's language.
    let title =
      StarSeparation.title(of: step.processID, locale: locale)
      ?? ProcessKitResources.title(model.title(of: step.processID), locale: locale)
    return Button {
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
    // No step lies under a moved preview's pixels: the row says why it is greyed (R2).
    .disabled(model.showsMovedGrid)
    .help(model.showsMovedGrid ? Text(UserFacingError.movedPreview.message) : Text(verbatim: ""))
    .accessible(.studioStep(index), label: title)
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
