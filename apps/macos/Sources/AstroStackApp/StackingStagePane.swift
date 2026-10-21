internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Empilement stage: the preset and its knobs the run uses, Run and Cancel, and the run as
/// it goes.
struct StackingStagePane: View {
  var model: ProjectWindowModel

  private var running: Bool { model.run?.isRunning == true }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header.padding(DesignMetrics.spacingM)
      HStack(spacing: 0) {
        // The values a run applies stay in view, frozen while it runs (R2).
        KnobPanel(model: model.knobs).frame(width: 300).disabled(running)
        Divider()
        if let run = model.run {
          RunPanel(run: run)
        } else {
          EmptyState(
            .app("Stacking"),
            message: .app(
              "Run calibrates, grades and stacks the nights, each step with its journal."),
            systemImage: "square.3.layers.3d")
        }
      }
    }
  }

  private var header: some View {
    @Bindable var knobs = model.knobs
    return HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
      SectionHeader(
        .app("Stacking"),
        detail: .app("Masters, stacks and the bundle are written inside the project."))
      Spacer()
      Picker(.app("Preset"), selection: $knobs.mode) {
        Text(.app("Deep sky")).tag(PreprocessRequest.Mode.deepsky)
        Text(.app("Nebula")).tag(PreprocessRequest.Mode.nebula)
      }
      .fixedSize()
      .disabled(running)
      if running {
        Button(.app("Cancel"), role: .cancel) { model.cancelRun() }
      } else {
        Button(.app("Run")) { model.startRun() }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canRun)
      }
    }
  }
}
