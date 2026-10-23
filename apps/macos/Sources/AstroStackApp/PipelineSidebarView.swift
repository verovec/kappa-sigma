internal import ProcessKit
internal import RenderKit
package import SwiftUI

/// The Studio's pipeline column (card 0088): the steps done, current and next, each with its
/// breakpoint and lock; Run, Continue, Replay; save, load and compare the pipeline.
package struct PipelineSidebarView: View {
  let model: PipelineSidebarModel
  @Environment(\.locale) private var locale
  @Environment(\.undoManager) private var undoManager
  @State private var naming = false
  @State private var name = ""
  @State private var comparedWith: String?

  /// The column of `model`.
  package init(model: PipelineSidebarModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      HStack {
        SectionHeader(.app("Pipeline"))
        Spacer()
        files
      }
      let problems = model.stepProblems
      ForEach(Array(model.pipeline.steps.enumerated()), id: \.offset) { index, step in
        PipelineStepRow(model: model, index: index, step: step, problems: problems[index])
      }
      ForEach(model.warnings, id: \.self) { warning in
        Text(verbatim: warning).font(.caption).foregroundStyle(DesignColor.statusAttention.color)
      }
      if let failure = model.failure { StatusBadge(.error, failure) }
      controls
    }
    .padding(DesignMetrics.spacingS)
    .alert(Text(.app("Save pipeline as")), isPresented: $naming) {
      TextField(text: $name) { Text(.app("Name")) }
        .accessible(.studioPipelineName, label: .app("Name"))
      Button(.app("Save")) { if !name.isEmpty { model.save(as: name) } }
        .accessible(.studioPipelineSave, label: .app("Save"))
      Button(.app("Cancel"), role: .cancel) {}
        .accessible(.studioPipelineCancel, label: .app("Cancel"))
    }
    .sheet(item: Binding(get: { comparedWith.map(Compared.init) }, set: { comparedWith = $0?.id }))
    { compared in
      PipelineDiffSheet(model: model, savedName: compared.id) { comparedWith = nil }
    }
  }

  private var controls: some View {
    HStack {
      Button(.app("Run")) { Task { await model.run(undoManager: undoManager) } }
        .disabled(model.isRunning)
        .accessible(.studioPipelineRun, label: .app("Run Pipeline"))
      // On a new head Continue previews the breakpoint's values first, and says so.
      let previews = model.workspace.isPreviewSuspended
      Button(previews ? .app("Preview") : .app("Continue")) {
        Task { await model.continueRun(undoManager: undoManager) }
      }
      .disabled(model.isRunning || !model.canContinue)
      .accessible(
        .studioPipelineContinue, label: previews ? .app("Preview") : .app("Continue Pipeline"))
      Spacer()
      Button(.app("Replay on…")) { model.onReplay() }
        .disabled(model.isRunning)
        .accessible(.studioPipelineReplay, label: .app("Replay Pipeline…"))
    }
  }

  private var files: some View {
    Menu {
      Button(.app("Save pipeline as…")) {
        name = model.pipeline.name
        naming = true
      }
      .accessible(.studioPipelineSaveAs, label: .app("Save pipeline as…"))
      let saved = model.savedNames
      if !saved.isEmpty {
        Menu(.app("Load")) { savedItems(saved, compare: false) }
          .accessible(.studioPipelineLoad, label: .app("Load"))
        Menu(.app("Compare with")) { savedItems(saved, compare: true) }
          .accessible(.studioPipelineCompare, label: .app("Compare with"))
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessible(.studioPipelineFiles, label: .app("Pipeline files"))
  }

  /// The saved pipelines as menu items: loaded, or compared with the one shown.
  private func savedItems(_ names: [String], compare: Bool) -> some View {
    ForEach(Array(names.enumerated()), id: \.offset) { offset, name in
      Button {
        if compare { comparedWith = name } else { model.load(name) }
      } label: {
        Text(verbatim: name)
      }
      .accessible(
        .studioPipelineSaved(offset, compare: compare),
        label: compare ? .app("Compare with") : .app("Load"))
    }
  }

  /// A saved pipeline the compare sheet shows.
  private struct Compared: Identifiable {
    let id: String
  }
}
