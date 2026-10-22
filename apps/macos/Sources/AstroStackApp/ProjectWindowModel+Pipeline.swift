internal import Foundation
package import ProcessKit
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
  /// nights kept while the history follows it, else the steps its history already holds (the
  /// user's work as the recipe), saying which profile it left.
  func sidebar(
    of workspace: StudioWorkspaceModel, stackID: Int64, store: ProjectStore,
    roles: Set<LayerRole>
  ) throws -> PipelineSidebarModel {
    let applied = workspace.studio.steps.map {
      Recipe(processID: $0.processID, params: $0.params)
    }
    let (pipeline, warnings) = Self.pipeline(
      applied: applied, profile: keptProfile(of: stackID)?.pipeline)
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: pipeline, warnings: warnings, store: store, base: roles)
    sidebar.onReplay = { [weak self] in self?.isChoosingReplay = true }
    return sidebar
  }

  /// The pipeline a history of `applied` steps shows: `profile` while the history follows it,
  /// else the history's own steps (with a warning naming the profile it left).
  package static func pipeline(applied: [Recipe], profile: Pipeline?) -> (Pipeline, [String]) {
    let own = Pipeline(name: "Studio", steps: applied.map { PipelineStep(recipe: $0) })
    guard let profile else { return (own, []) }
    let planned = profile.steps.prefix(applied.count).map(\.recipe.processID)
    if applied.count <= profile.steps.count, applied.map(\.processID) == Array(planned) {
      return (profile, [])
    }
    return (own, ["the history left the pipeline of profile \(profile.name): its own steps"])
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
