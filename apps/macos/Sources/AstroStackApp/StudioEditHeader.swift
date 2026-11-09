internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// The panel of an applied step being edited (card 0159): « Step 3 · Stretch — editing », what
/// Apply replays and where it stops, the preview's stop banner (0158), the recorded mask, and
/// Cancel / Apply change in place of Close / Apply.
struct StudioEditHeader: View {
  /// The help card of the history's « ? » (`stage/re-edit.md`).
  nonisolated static let helpCard = "re-edit"

  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      if let title = model.editTitle(locale: locale) {
        Text(title).font(.headline)
      }
      ForEach(Array(model.editSummary(locale: locale).enumerated()), id: \.offset) { _, line in
        Text(line).font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      }
      if let notice = model.chainStopNotice(locale: locale) { StatusBadge(.attention, notice) }
      if model.chainPreviewReduced {
        StatusBadge(.attention, .app("Reduced preview while adjusting — full resolution at rest"))
      }
      if model.editUsesRecordedMask {
        StatusBadge(.ok, .app("Edited under the mask it was applied with"))
      }
    }
  }
}

/// Cancel / Apply change: the edit's own buttons (card 0159), Apply change greyed like Apply
/// with its reason (a run moving the image, a choice still to make).
struct StudioEditButtons: View {
  let model: StudioWorkspaceModel
  @Environment(\.undoManager) private var undoManager
  @Environment(\.locale) private var locale

  var body: some View {
    let blocked = model.applyEditRefusal(locale: locale)
    HStack {
      Button(.app("Cancel")) { model.cancelEdit() }
        .accessible(.studioEditCancel, label: .app("Cancel"))
      Spacer()
      Button(.app("Apply Change")) {
        Task { await StudioUndo.applyEdit(model, on: undoManager) }
      }
      .disabled(model.isMovingHistory || model.toolRun != nil || blocked != nil)
      .help(blocked.map { Text($0) } ?? Text(verbatim: ""))
      .accessible(.studioEditApply, label: .app("Apply Change"))
    }
  }
}
