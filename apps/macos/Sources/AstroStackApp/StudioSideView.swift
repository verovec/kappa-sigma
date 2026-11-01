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
        panelSection
        if let notice = model.staleNotice { stale(notice) }
        if let failure = model.failure { StatusBadge(.error, failure) }
        if model.appliedNothing {
          StatusBadge(.attention, .app("These values changed nothing: Undo takes the step back."))
        }
        history
      }
      .padding(DesignMetrics.spacingM)
    }
  }

  /// The chosen process's panel with Close / Apply, or an applied step re-edited (card 0159)
  /// with its header and Cancel / Apply change; a hint without a panel.
  @ViewBuilder private var panelSection: some View {
    if let panel = model.panel, model.editedStep != nil {
      StudioEditHeader(model: model)
      ProcessPanel(model: panel)
      rows(under: panel)
      StudioEditButtons(model: model)
      if model.isPreviewSuspended { suspended }
    } else if let panel = model.panel {
      ProcessPanel(model: panel)
      rows(under: panel)
      HStack {
        Button(.app("Close")) { model.closePanel() }
          .accessible(.studioClosePanel, label: .app("Close"))
        Spacer()
        // No default-button Return: Return confirms a typed value (Edit › Apply Process ⌘E).
        // On a new head Apply previews first, and says so.
        let title: LocalizedStringResource =
          model.isPreviewSuspended ? .app("Preview") : .app("Apply")
        let blocked = blocked(panel)
        Button(title) { applyRecorded() }
          .disabled(model.toolRun != nil || blocked != nil)
          .help(blocked.map { Text($0) } ?? Text(verbatim: ""))
          .accessible(.studioApply, label: title)
      }
      StudioToolRow(model: model)
      if model.isPreviewSuspended { suspended }
    } else {
      Text(.app("Choose a process in the catalogue."))
        .foregroundStyle(DesignColor.textSecondary.color)
    }
  }

  /// Why Apply is greyed: a host tool under a mask, or a choice still to make (card 0140) —
  /// greyed with the reason, not refused after.
  private func blocked(_ panel: ProcessPanelModel) -> LocalizedStringResource? {
    guard panel.type.runsTool(panel.params) else { return nil }
    return model.toolRefusal ?? model.unchosenRefusal(panel, locale: locale)
  }

  /// What the panel's process asks for below its parameters: the mask row, or its own rows —
  /// and, where the process takes no mask, the mask still set with its Clear (card 0111).
  @ViewBuilder
  private func rows(under panel: ProcessPanelModel) -> some View {
    if model.selection != .main {
      StudioInactiveMaskRow(model: model, kind: .branch)
    } else if model.editedStep != nil {
      // The edit replays the step under the mask it recorded, if any (the header says so):
      // the mask row would draw another one, never applied.
      EmptyView()
    } else if panel.type is any GeometricProcess.Type {
      // Geometry moves the whole grid: no mask, the output's size and solution instead
      // (none while the values leave no pixel: the panel shows that failure).
      StudioInactiveMaskRow(model: model, kind: .ignored)
      if let output = model.geometryOutput { GeometryExtras(model: model, output: output) }
    } else if let kind = StudioInactiveMaskRow.kind(for: panel.type, params: panel.params) {
      // A host tool (extraction, plate solve, SPCC) works on the whole image: no mask.
      StudioInactiveMaskRow(model: model, kind: kind)
      // The extraction runs on its layers too: its own rows.
      if panel.type.id == BackgroundExtractionProcess.id { StudioBatchRows(model: model) }
    } else {
      StudioMaskRow(model: model)
    }
  }

  /// A branch edit outdated main steps (card 0119): which, and why; Replay runs them again with
  /// their recorded values — never by itself (R2).
  private func stale(_ notice: StaleNotice) -> some View {
    let steps = notice.steps.map { AstroFormat(locale: locale).integer($0 + 1) }
      .joined(separator: ", ")
    let branches = notice.branches.map { StudioSelection.label(.branch($0), locale: locale) }
      .joined(separator: ", ")
    return VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      StatusBadge(
        .attention,
        .app(
          "Stale steps: \(steps) (they read \(branches), changed since). Replay runs them again."
        ))
      Button(.app("Replay")) {
        Task { try? await StudioUndo.replayMain(model, on: undoManager) }
      }
      .disabled(model.isMovingMain || model.toolRun != nil)
      .accessible(.studioReplayStale, label: .app("Replay"))
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
        SectionHeader(
          .app("History"), help: StageHelp.help(card: StudioEditHeader.helpCard, locale: locale))
        Spacer()
        if !model.versions.isEmpty { StudioVersionsMenu(model: model) }
        // A run or a host tool moving the history: the move waits, as Edit › Undo does.
        Button(.app("Undo")) { undo() }
          .disabled(!model.studio.canUndo(on: model.selection) || model.isMovingHistory)
          .accessible(.studioUndo, label: .app("Undo"))
        Button(.app("Redo")) { redo() }
          .disabled(!model.studio.canRedo(on: model.selection) || model.isMovingHistory)
          .accessible(.studioRedo, label: .app("Redo"))
      }
      ForEach(Array(model.steps.enumerated()), id: \.offset) { index, step in
        stepRow(index, step)
      }
    }
  }

  /// One applied step: its number and title; a click edits it (card 0159), its eye button (or
  /// ⌥-click) compares the viewer with its output.
  private func stepRow(_ index: Int, _ step: History.Step) -> some View {
    let title = model.stepTitle(of: step.processID, locale: locale)
    return HStack {
      Button {
        // A branch's steps are compared, never edited (E25 edits the combined image only).
        if NSEvent.modifierFlags.contains(.option) || model.selection != .main {
          model.toggleCompare(index)
        } else {
          model.editStep(index)
        }
      } label: {
        HStack {
          Text(verbatim: "\(index + 1).")
          Text(title).fontWeight(model.editedStep == index ? .bold : .regular)
          if model.isRecomputed(index) {
            Text(.app("To recompute")).font(.caption)
              .foregroundStyle(DesignColor.textSecondary.color)
          }
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(model.isMovingHistory)
      .help(Text(.app("Edit this step; ⌥-click compares")))
      .accessible(.studioStep(index), label: title)
      compareButton(index, title: title)
    }
  }

  /// The eye of a history row: compares the viewer with the step's output, or stops.
  private func compareButton(_ index: Int, title: LocalizedStringResource) -> some View {
    Button {
      model.toggleCompare(index)
    } label: {
      if model.comparing == index {
        Image(systemName: "eye.fill")
      } else {
        Image(systemName: "eye")
      }
    }
    .buttonStyle(.plain)
    // No step lies under a moved preview's pixels: the eye says why it is greyed (R2).
    .disabled(model.showsMovedGrid)
    .help(
      model.showsMovedGrid
        ? Text(UserFacingError.movedPreview.message) : Text(.app("Compare"))
    )
    .accessible(.studioStepCompare(index), label: .app("Compare"))
  }

  /// Applies the panel and records the step with the window's undo manager, so ⌘Z / ⇧⌘Z reach
  /// the history too.
  private func applyRecorded() {
    StudioUndo.apply(model, undoManager: undoManager)
  }

  /// One step back: ⌘Z when the last action is this Studio's step back, so the menu follows the
  /// button.
  private func undo() {
    StudioUndo.undo(model, undoManager: undoManager)
  }

  private func redo() {
    StudioUndo.redo(model, undoManager: undoManager)
  }
}
