/// A finished or stopped run (card 0059): its history and the bundle it ran against — what a
/// later replay's locked steps may be taken from, only when the new run has the same input.
package struct PipelineRun {
  /// The history the pipeline was applied to.
  package let history: History
  /// The bundle it ran against.
  package let bundle: PipelineBundle

  /// The run of `history` against `bundle`.
  package init(history: History, bundle: PipelineBundle) {
    self.history = history
    self.bundle = bundle
  }
}
