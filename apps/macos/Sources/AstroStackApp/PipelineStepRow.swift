internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// One step of the pipeline column (card 0088): done ✓, current ▶ or next, its process, its
/// breakpoint and lock; a step that cannot run is greyed with its reason (R2: shown, never
/// fixed); a batch step shows its progress while it runs.
///
/// A step not applied yet is removed or moved from its context menu, or removed with ⌫ (card
/// 0107).
struct PipelineStepRow: View {
  let model: PipelineSidebarModel
  let index: Int
  let step: PipelineStep
  let problems: [String]
  @Environment(\.locale) private var locale
  @Environment(\.undoManager) private var undoManager

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: DesignMetrics.spacingXS) {
        statusImage.frame(width: 16)
        Text(verbatim: "\(index + 1).")
        Text(title).lineLimit(1)
        Spacer()
        modeButton
        lockButton
      }
      if let fraction = model.progress[index], model.isRunning {
        ProgressView(value: fraction)
      }
      ForEach(problems, id: \.self) { problem in
        Text(verbatim: problem).font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      }
    }
    .opacity(problems.isEmpty ? 1 : 0.5)
    .contentShape(Rectangle())
    .contextMenu { editMenu }
    .focusable(model.canEdit(index))
    .onDeleteCommand { model.remove(at: index, undoManager: undoManager) }
  }

  /// Remove, move up, move down; on an applied step, disabled with the reason (R2: shown).
  @ViewBuilder private var editMenu: some View {
    let refusal = model.editRefusal(of: index)
    Button(.app("Remove step")) { model.remove(at: index, undoManager: undoManager) }
      .disabled(refusal != nil)
      .accessible(.studioPipelineStepRemove(index), label: .app("Remove step"))
    Button(.app("Move up")) { model.move(from: index, to: index - 1, undoManager: undoManager) }
      .disabled(!model.canEdit(index) || !model.canEdit(index - 1))
      .accessible(.studioPipelineStepMove(index, up: true), label: .app("Move up"))
    Button(.app("Move down")) { model.move(from: index, to: index + 1, undoManager: undoManager) }
      .disabled(!model.canEdit(index) || !model.canEdit(index + 1))
      .accessible(.studioPipelineStepMove(index, up: false), label: .app("Move down"))
    if let refusal { Text(refusal) }
  }

  /// Halts the run before this step, or not.
  private var modeButton: some View {
    Button {
      model.setMode(step.mode == .stop ? .auto : .stop, of: index)
    } label: {
      if step.mode == .stop {
        Image(systemName: "pause.circle.fill")
      } else {
        Image(systemName: "pause.circle")
      }
    }
    .buttonStyle(.plain)
    .accessible(.studioPipelineStep(index, lock: false), label: .app("Breakpoint"))
  }

  /// Keeps this step's output on replay, or not.
  private var lockButton: some View {
    Button {
      model.setLocked(!step.locked, of: index)
    } label: {
      if step.locked {
        Image(systemName: "lock.fill")
      } else {
        Image(systemName: "lock.open")
      }
    }
    .buttonStyle(.plain)
    .accessible(.studioPipelineStep(index, lock: true), label: .app("Locked on replay"))
  }

  private var title: LocalizedStringResource {
    ProcessKitResources.title(model.workspace.title(of: step.recipe.processID), locale: locale)
  }

  @ViewBuilder private var statusImage: some View {
    switch model.status(of: index) {
    case .done: Image(systemName: "checkmark.circle.fill")
    case .stale:
      Image(systemName: "exclamationmark.arrow.circlepath")
        .foregroundStyle(DesignColor.textSecondary.color)
    case .current: Image(systemName: "play.circle.fill")
    case .next: Image(systemName: "circle")
    }
  }
}
