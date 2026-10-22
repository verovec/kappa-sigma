/// What a run reports while it works, in order, on the stream of a `Preprocessor`.
package enum PreprocessEvent: Equatable, Sendable {
  /// A step began, a percentage moved or a journal line arrived.
  case progress(Progress)
  /// A quick-look PNG of a stage's output is ready.
  case preview(Preview)
  /// A lane's frames are graded and the run waits for the user's decision (card 0069).
  case frames(Frames)
  /// A lane's frames are measured and the run waits for the reference pin before applying the
  /// registration (card 0096).
  case reference(Reference)
  /// The run finished; the last event.
  case finished(PreprocessResult)

  /// A lane paused before its registration is applied: every frame as Siril measured it (not
  /// graded), its night and parity, the frame the port elected, and the gate that resumes the
  /// run with a pin (`FrameGrade.index`) or nil to keep the election.
  package struct Reference: Equatable, Sendable {
    /// The lane (filter) under review.
    package var lane: String
    /// One measured frame per input frame, in sequence order; `rejected` is never set here.
    package var candidates: [FrameGrade]
    /// Each frame registered with a transform, parallel to `candidates`: the only frames a pin
    /// may name (`ReferencePinContext.accepts`).
    package var registered: [Bool]
    /// Each frame's capture night, parallel to `candidates`.
    package var nights: [String]
    /// Each frame's parity against the run's convention, parallel to `candidates`.
    package var parity: [FrameParity]
    /// The frame the port would register onto, as `FrameGrade.index`; nil when unknown.
    package var elected: Int?
    /// Answers the pause.
    package var gate: ReferencePinGate

    /// A pause of `lane`.
    package init(
      lane: String, candidates: [FrameGrade], registered: [Bool], nights: [String],
      parity: [FrameParity], elected: Int?, gate: ReferencePinGate
    ) {
      self.lane = lane
      self.candidates = candidates
      self.registered = registered
      self.nights = nights
      self.parity = parity
      self.elected = elected
      self.gate = gate
    }
  }

  /// A lane paused at the frame-review breakpoint: every grade as the grader left it, the
  /// elected reference, a thumbnail per registered frame, and the gate that resumes the run.
  package struct Frames: Equatable, Sendable {
    /// The lane (filter) under review.
    package var lane: String
    /// One grade per input frame, in sequence order, as graded (before any decision).
    package var grades: [FrameGrade]
    /// The capture nights as positions in `grades` (one span per night; one span alone for a
    /// single night).
    package var spans: [Range<Int>]
    /// Each frame's capture night (`CaptureFrame.session`), parallel to `grades`.
    package var nights: [String]
    /// The registration reference as `FrameGrade.index`; nil when Siril's sequence does not say.
    package var elected: Int?
    /// A quick-look PNG per frame, parallel to `grades`; nil for a frame Siril could not register.
    package var thumbnails: [String?]
    /// Answers the pause.
    package var gate: FrameReviewGate

    /// A pause of `lane`.
    package init(
      lane: String, grades: [FrameGrade], spans: [Range<Int>], nights: [String], elected: Int?,
      thumbnails: [String?], gate: FrameReviewGate
    ) {
      self.lane = lane
      self.grades = grades
      self.spans = spans
      self.nights = nights
      self.elected = elected
      self.thumbnails = thumbnails
      self.gate = gate
    }
  }

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
