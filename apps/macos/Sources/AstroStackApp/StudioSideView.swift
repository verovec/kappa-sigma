internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// The Studio's right column (card 0087): the chosen process's panel with Apply, then the
/// history — each step comparable, Undo and Redo.
struct StudioSideView: View {
  let model: StudioWorkspaceModel
  @Environment(\.undoManager) private var undoManager
  @Environment(\.locale) private var locale

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
        if let panel = model.panel {
          ProcessPanel(model: panel)
          HStack {
            Button(.app("Close")) { model.closePanel() }
              .accessible(.studioClosePanel, label: .app("Close"))
            Spacer()
            Button(.app("Apply")) { applyRecorded() }
              .keyboardShortcut(.defaultAction)
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
        let title = ProcessKitResources.title(
          ProcessRegistryTitles.title(of: step.processID), locale: locale)
        Button {
          try? model.compare(toStep: model.comparing == index ? nil : index)
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
    guard (try? model.apply()) != nil else { return }
    record(undoing: true)
  }

  /// Registers the inverse of the last move: an undo after an apply or a redo, a redo after an
  /// undo.
  private func record(undoing: Bool) {
    let model = model
    undoManager?.registerUndo(withTarget: model) { target in
      MainActor.assumeIsolated {
        guard (try? undoing ? target.undo() : target.redo()) != nil else { return }
        Self(model: target).record(undoing: !undoing)
      }
    }
  }

  /// One step back: through the undo manager when it holds the step, else on the history
  /// itself (a reopened project's steps were applied in an earlier session).
  private func undo() {
    if let undoManager, undoManager.canUndo {
      undoManager.undo()
    } else {
      try? model.undo()
    }
  }

  private func redo() {
    if let undoManager, undoManager.canRedo {
      undoManager.redo()
    } else {
      try? model.redo()
    }
  }
}

/// The titles of the registry's processes by id (a step names its process by id).
enum ProcessRegistryTitles {
  static let titles: [String: String] = {
    let types = (try? ProcessRegistry.standard().types) ?? []
    return Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0.title) })
  }()

  static func title(of id: String) -> String { titles[id] ?? id }
}
