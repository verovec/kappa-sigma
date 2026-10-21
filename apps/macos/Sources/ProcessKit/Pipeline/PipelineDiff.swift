/// The differences between two pipelines, step by step (card 0059): what the diff view lists.
package enum PipelineDiff {
  /// One difference at a step.
  package struct Entry: Equatable, Sendable {
    /// The step index (in the longer pipeline for added / removed steps).
    package let step: Int
    /// The step's process (the right-hand one when they differ).
    package let processID: String
    /// What differs.
    package let change: Change

    /// A difference `change` at `step` of `processID`.
    package init(step: Int, processID: String, change: Change) {
      self.step = step
      self.processID = processID
      self.change = change
    }
  }

  /// What differs at a step.
  package enum Change: Equatable, Sendable {
    /// Parameter `id`: left value, right value (`nil` when one side does not have it).
    case param(String, ParamValue?, ParamValue?)
    /// The breakpoint mode.
    case mode(PipelineStep.Mode, PipelineStep.Mode)
    /// The lock.
    case locked(Bool, Bool)
    /// Another process at this place: left id, right id.
    case process(String, String)
    /// The step exists on the right only.
    case added
    /// The step exists on the left only.
    case removed
  }

  /// Every difference from `lhs` to `rhs`, step order, parameters in panel order.
  package static func entries(_ lhs: Pipeline, _ rhs: Pipeline) -> [Entry] {
    var entries: [Entry] = []
    for index in 0..<max(lhs.steps.count, rhs.steps.count) {
      switch (lhs.steps.indices.contains(index), rhs.steps.indices.contains(index)) {
      case (true, true):
        entries += step(index, lhs.steps[index], rhs.steps[index])
      case (false, true):
        entries.append(
          Entry(step: index, processID: rhs.steps[index].recipe.processID, change: .added))
      default:
        entries.append(
          Entry(step: index, processID: lhs.steps[index].recipe.processID, change: .removed))
      }
    }
    return entries
  }

  private static func step(_ index: Int, _ lhs: PipelineStep, _ rhs: PipelineStep) -> [Entry] {
    let id = rhs.recipe.processID
    guard lhs.recipe.processID == id else {
      return [Entry(step: index, processID: id, change: .process(lhs.recipe.processID, id))]
    }
    var entries: [Entry] = []
    if lhs.mode != rhs.mode {
      entries.append(Entry(step: index, processID: id, change: .mode(lhs.mode, rhs.mode)))
    }
    if lhs.locked != rhs.locked {
      entries.append(Entry(step: index, processID: id, change: .locked(lhs.locked, rhs.locked)))
    }
    let left = Dictionary(lhs.recipe.params.map { ($0.id, $0.value) }) { first, _ in first }
    let right = Dictionary(rhs.recipe.params.map { ($0.id, $0.value) }) { first, _ in first }
    let ids = rhs.recipe.params.map(\.id) + lhs.recipe.params.map(\.id).filter { right[$0] == nil }
    for param in ids where left[param] != right[param] {
      entries.append(
        Entry(step: index, processID: id, change: .param(param, left[param], right[param])))
    }
    return entries
  }
}
