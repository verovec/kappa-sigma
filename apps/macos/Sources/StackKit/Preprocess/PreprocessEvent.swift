/// What a run reports while it works, in order, on the stream of a `Preprocessor`.
package enum PreprocessEvent: Equatable, Sendable {
  /// A step began, a percentage moved or a journal line arrived.
  case progress(Progress)
  /// A quick-look PNG of a stage's output is ready.
  case preview(Preview)
  /// The run finished; the last event.
  case finished(PreprocessResult)

  /// A step's progress.
  package struct Progress: Equatable, Sendable {
    /// 1-based position of the step in the run.
    package var step: Int
    package var steps: Int
    package var title: String
    /// Siril's percentage, when the line carried one.
    package var percent: Int?
    /// The journal line; empty when the step only began.
    package var line: String

    /// Step `step` of `steps`, with a journal `line` (empty when the step only began).
    package init(step: Int, steps: Int, title: String, percent: Int?, line: String) {
      self.step = step
      self.steps = steps
      self.title = title
      self.percent = percent
      self.line = line
    }
  }

  /// A stage's quick look.
  package struct Preview: Equatable, Sendable {
    /// The stage that produced it (`master_L`, `combined`).
    package var stage: String
    package var pngPath: String

    /// The quick look of `stage` at `pngPath`.
    package init(stage: String, pngPath: String) {
      self.stage = stage
      self.pngPath = pngPath
    }
  }
}
