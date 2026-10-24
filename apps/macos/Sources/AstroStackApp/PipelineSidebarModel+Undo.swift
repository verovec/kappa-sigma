package import ProcessKit

/// Card 0117: a run undone or redone puts the column back with the history — its breakpoint and
/// the values a Continue wrote, the pipeline a replay replaced — so Continue is offered again
/// where it was.
extension PipelineSidebarModel {
  /// Where the column stands before or after a run.
  package struct Mark: Sendable {
    /// The breakpoint the run halted at, with the process of its step.
    package let stopped: (index: Int, processID: String)?
    /// The recipes kept, by step: the one a Continue wrote.
    package let recipes: [Int: Recipe]
    /// The whole pipeline, kept when a replay replaces it.
    package let pipeline: Pipeline?
  }

  /// The column now, with the recipes of `steps`, and its whole pipeline when `whole`.
  package func mark(keeping steps: some Sequence<Int> = [], whole: Bool = false) -> Mark {
    let recipes = steps.filter(pipeline.steps.indices.contains).map {
      ($0, pipeline.steps[$0].recipe)
    }
    let stopped = stoppedAt.flatMap { index in
      pipeline.steps.indices.contains(index)
        ? (index, pipeline.steps[index].recipe.processID) : nil
    }
    return Mark(
      stopped: stopped, recipes: Dictionary(uniqueKeysWithValues: recipes),
      pipeline: whole ? pipeline : nil)
  }

  /// Puts the column back at `mark`: its pipeline when it kept one, its recipes on the steps
  /// still running the same process, and the breakpoint — on its own step only — with its
  /// process in the panel, as the run halted there.
  package func restore(_ mark: Mark) {
    if let whole = mark.pipeline { pipeline = whole }
    for (index, recipe) in mark.recipes
    where pipeline.steps.indices.contains(index)
      && pipeline.steps[index].recipe.processID == recipe.processID
    {
      pipeline.steps[index].recipe = recipe
    }
    guard let stopped = mark.stopped, pipeline.steps.indices.contains(stopped.index),
      pipeline.steps[stopped.index].recipe.processID == stopped.processID
    else {
      stoppedAt = nil
      return
    }
    halt(at: stopped.index)
  }

  /// Halts before step `index`, its recipe in the panel.
  func halt(at index: Int) {
    stoppedAt = index
    let recipe = pipeline.steps[index].recipe
    guard let type = workspace.registry.type(id: recipe.processID) else { return }
    workspace.choose(
      recipe.processID, params: ParamSet.loading(recipe.params, onto: type.schema).params)
  }
}
