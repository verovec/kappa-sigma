internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The Empilement stage: the series the run stacks (card 0095), the preset and its knobs, Run
/// and Cancel, and the run as it goes.
struct StackingStagePane: View {
  var model: ProjectWindowModel
  @Environment(\.locale) private var locale

  /// A run or a queue is going: the panel is frozen and Cancel offered until the last run ends.
  private var running: Bool { model.isStacking }

  /// « Run » for one run; « Stack 2 objects (2 runs) » once the series span several (0095).
  private var runWords: LocalizedStringResource {
    let runs = model.series.scopes.count
    return runs > 1 ? .app("Stack \(runs) objects (\(runs) runs)") : .app("Run")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      notices
      HStack(spacing: 0) {
        // The values a run applies stay in view, frozen while it runs (R2).
        ScrollView {
          VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
            StackingSeriesView(model: model.series).padding(DesignMetrics.spacingM)
              .disabled(running)
            KnobPanel(model: model.knobs, lanes: model.series.laneColumns, frozen: running)
          }
        }
        .frame(width: 300)
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

  /// The stage's title and help, the preset and Run.
  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
      SectionHeader(
        .app("Stacking"),
        detail: .app("Masters, stacks and the bundle are written inside the project."),
        help: StageHelp.help(.stacking, locale: locale))
      Spacer()
      controls
    }
    .padding(DesignMetrics.spacingM)
  }

  /// Why Run is greyed, the paused runs to continue (card 0097), what the run redoes (card 0100)
  /// and the scratch it needs (card 0098); nothing while a run goes.
  @ViewBuilder private var notices: some View {
    blocker
    if !running && !model.pausedRuns.isEmpty { PausedRunsView(model: model) }
    if !running && model.awaitsRescan {
      notice(.app("Rescanning every night after the new one: the next run’s plan follows."))
    } else if model.canRun && !model.needsSave, let plan = model.restackPlan {
      RestackLine(plan: plan)
    }
    if !running, let budget = model.scratchBudget { ScratchBudgetLine(budget: budget) }
    if !running && !model.leftoverStacks.isEmpty { StackLeftoversView(model: model) }
  }

  /// Why Run is greyed, with the one action that ungreys it; nothing while a run goes.
  @ViewBuilder private var blocker: some View {
    if !running && model.nightPaths.isEmpty && !model.sources.isEmpty {
      notice(.app("Import a capture night to stack: a legacy run is shown, never stacked again."))
    } else if !running && model.nightPaths.isEmpty {
      notice(.app("Import a capture night to stack."))
    } else if !running && model.needsSave {
      HStack(alignment: .firstTextBaseline) {
        notice(.app("Save the project first: its masters and stacks are written inside it."))
        Button(.app("Save…")) { model.save() }
          .accessible(.stackingSave, label: .app("Save…"))
      }
      .padding(.trailing, DesignMetrics.spacingM)
    } else if !running && !model.series.isEmpty && model.series.scopes.isEmpty {
      notice(.app("Check at least one series to stack."))
    } else if !running && model.needsSeries {
      notice(
        .app("This project stacks several objects: Rescan (Données › Rescan) to choose the series.")
      )
    }
  }

  private func notice(_ text: LocalizedStringResource) -> some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: "info.circle")
    }
    .foregroundStyle(DesignColor.statusAttention.color)
    .padding([.horizontal, .bottom], DesignMetrics.spacingM)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The preset, then Run — or Cancel while a run goes.
  @ViewBuilder private var controls: some View {
    @Bindable var knobs = model.knobs
    Picker(.app("Preset"), selection: $knobs.mode) {
      Text(.app("Deep sky")).tag(PreprocessRequest.Mode.deepsky)
      Text(.app("Nebula")).tag(PreprocessRequest.Mode.nebula)
    }
    .fixedSize()
    .disabled(running)
    .accessible(.stackingPreset, label: .app("Preset"))
    if running {
      if model.run?.pauseRequested == true {
        Text(.app("Pausing after the current lane…")).foregroundStyle(.secondary)
      } else {
        // A lane is never cut: the run stops once its current master is written (card 0097).
        Button(.app("Pause")) { model.pauseRun() }
          .disabled(model.run?.canPause != true)
          .accessible(.stackingPause, label: .app("Pause"))
      }
      Button(.app("Cancel"), role: .cancel) { model.cancelRun() }
        .accessible(.stackingCancel, label: .app("Cancel"))
    } else {
      Button(runWords) { model.startRun() }
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canRun || model.needsSave)
        .accessible(.stackingRun, label: runWords)
    }
  }
}
