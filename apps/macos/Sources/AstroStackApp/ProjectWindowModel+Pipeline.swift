internal import Foundation
internal import ProcessKit
package import ProjectKit

/// A pipeline the user replays on another stack (card 0088): run once that stack's working
/// image is loaded, its locked steps reused from `previous` when the input is the same.
struct PendingReplay {
  /// The stack it runs on.
  let stackID: Int64
  /// The pipeline, as the column showed it.
  let pipeline: Pipeline
  /// The run its locked steps come from.
  let previous: PipelineRun?
}

extension ProjectWindowModel {
  /// The pipeline column of `workspace` (stack `stackID`): the pipeline of the profile its
  /// nights kept, else the steps its history already holds (the user's work as the recipe).
  func sidebar(
    of workspace: StudioWorkspaceModel, stackID: Int64, store: ProjectStore,
    roles: Set<LayerRole>
  ) throws -> PipelineSidebarModel {
    let pipeline =
      keptProfile(of: stackID)?.pipeline
      ?? Pipeline(
        name: "Studio",
        steps: workspace.studio.steps.map {
          PipelineStep(recipe: Recipe(processID: $0.processID, params: $0.params))
        })
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: pipeline, store: store, base: roles)
    sidebar.onReplay = { [weak self] in self?.isChoosingReplay = true }
    return sidebar
  }

  /// The stacks the pipeline can be replayed on: the project's others, newest last.
  package var replayTargets: [ProjectStack] {
    stacks.filter { $0.id != workspaceStackID }
  }

  /// Replays the pipeline shown on stack `id`: the Studio switches to that stack and runs it
  /// there once its working image is loaded (the user's choice in the Replay menu).
  package func replayPipeline(on id: Int64) {
    guard let sidebar = workspace?.pipeline, replayTargets.contains(where: { $0.id == id })
    else { return }
    pendingReplay = PendingReplay(
      stackID: id, pipeline: sidebar.pipeline, previous: sidebar.lastRun)
    selectStack(id)
    select(.studio)
    Task { await openStudio() }
  }

  /// Runs the pending replay of stack `stackID`, if any, on its just loaded workspace.
  func replayIfPending(on stackID: Int64) async {
    guard let pending = pendingReplay, pending.stackID == stackID,
      let sidebar = workspace?.pipeline
    else { return }
    pendingReplay = nil
    sidebar.show(pending.pipeline)
    await sidebar.run(previous: pending.previous)
  }
}
