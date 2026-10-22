/// What a measured lane hands to the reference pin (card 0096) before its registration is
/// applied: every frame as Siril measured it, its night and parity, and the elected reference.
package struct ReferencePinContext: Sendable {
  /// The lane (filter).
  package var lane: String
  /// One measured frame per input frame, in sequence order (metrics only, never graded).
  package var candidates: [FrameGrade]
  /// Each frame registered with a transform (`RegistrationReview.registered`), parallel to
  /// `candidates`: the only frames a pin may name.
  package var registered: [Bool]
  /// Each frame's capture night, parallel to `candidates`.
  package var nights: [String]
  /// Each frame's parity against the run's convention, parallel to `candidates`.
  package var parity: [FrameParity]
  /// The frame the port would register onto, as `FrameGrade.index`; nil when unknown.
  package var elected: Int?

  /// A lane's pin context.
  package init(
    lane: String, candidates: [FrameGrade], registered: [Bool], nights: [String],
    parity: [FrameParity], elected: Int?
  ) {
    self.lane = lane
    self.candidates = candidates
    self.registered = registered
    self.nights = nights
    self.parity = parity
    self.elected = elected
  }

  /// The context of `sequence` as Siril measured it, one candidate per metric line, each with
  /// the capture frame's path and night; the arrays stay parallel even when the `.seq` has
  /// more or fewer lines than frames (a frame Siril could not open), padded with no night and
  /// no parity.
  package init(
    lane: String, sequence: SirilSequence, frames: [CaptureFrame], parity: [FrameParity],
    elected: Int?
  ) {
    let indices = sequence.metrics.indices
    let registered = RegistrationReview.registered(sequence.metrics)
    self.init(
      lane: lane,
      candidates: zip(indices, sequence.metrics).map { index, metric in
        FrameGrade(
          index: index + 1, path: index < frames.count ? frames[index].path : "",
          sequence: metric)
      },
      registered: indices.map(registered),
      nights: indices.map { $0 < frames.count ? frames[$0].session : "" },
      parity: indices.map { $0 < parity.count ? parity[$0] : .unprobed }, elected: elected)
  }

  /// The pin `index` names a frame registered with a transform.
  package func accepts(_ index: Int) -> Bool {
    index >= 1 && index <= registered.count && registered[index - 1]
  }
}
