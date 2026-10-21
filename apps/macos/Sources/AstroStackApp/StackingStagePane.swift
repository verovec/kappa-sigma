internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Empilement stage: the preset the run uses, Run and Cancel, and the run as it goes.
struct StackingStagePane: View {
  var model: ProjectWindowModel
  @State private var mode = PreprocessRequest.Mode.deepsky

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
        SectionHeader(
          .app("Stacking"),
          detail: .app("Masters, stacks and the bundle are written inside the project."))
        Spacer()
        controls
      }
      .padding(DesignMetrics.spacingM)
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  /// The preset, then Run — or Cancel while a run goes.
  @ViewBuilder private var controls: some View {
    Picker(.app("Preset"), selection: $mode) {
      Text(.app("Deep sky")).tag(PreprocessRequest.Mode.deepsky)
      Text(.app("Nebula")).tag(PreprocessRequest.Mode.nebula)
    }
    .fixedSize()
    .disabled(model.run?.isRunning == true)
    .accessible(.stackingPreset, label: .app("Preset"))
    if model.run?.isRunning == true {
      Button(.app("Cancel"), role: .cancel) { model.cancelRun() }
        .accessible(.stackingCancel, label: .app("Cancel"))
    } else {
      Button(.app("Run")) { model.startRun(mode: mode) }
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canRun)
        .accessible(.stackingRun, label: .app("Run"))
    }
  }
}
