/// When a locked step may keep its earlier output (card 0059).
///
/// Only when that output was made from the same input: `history` holds exactly the pipeline's
/// steps before `step`, `previous` ran the same process there, both started from the same image
/// against the same bundle, and every earlier step has the same process and values. Otherwise the step re-runs — copying in
/// pixels made from another image (another bundle, a changed earlier step) would be a hidden
/// change.
enum PipelineReuse {
  /// Whether step `step` of `previous` can be reused as the next step of `history`.
  static func canReuse(
    step: Int, of run: PipelineRun, into history: History, bundle: PipelineBundle,
    processID: String
  ) -> Bool {
    let previous = run.history
    guard history.steps.count == step, previous.steps.indices.contains(step),
      previous.steps[step].processID == processID, history.hasSameOriginal(as: previous),
      bundle.isSameInput(as: run.bundle)
    else { return false }
    return zip(previous.steps.prefix(step), history.steps).allSatisfy {
      $0.processID == $1.processID && $0.params == $1.params
    }
  }
}
