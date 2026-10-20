/// Names unlabeled lights by the wheel's fixed cyclic order (`internal/channeldetect`): frames come
/// in contiguous same-filter runs that advance through the order; brightness anchors the ends
/// (L brightest, narrowband faintest) and R/G/B fall out by position, never by brightness.
package enum ChannelDetector {
  /// The signal character of one frame.
  package struct Fingerprint: Equatable, Sendable {
    /// Robust sky level (median).
    package var background = 0.0
    /// Bright-signal proxy (P90 − median).
    package var flux = 0.0
    /// Fraction of bright pixels (broadband ≫ narrowband).
    package var starRichness = 0.0
    /// Robust noise (MAD).
    package var noise = 0.0
    package var exposureMs = 0

    /// A fingerprint; unset fields are zero.
    package init(
      background: Double = 0, flux: Double = 0, starRichness: Double = 0, noise: Double = 0,
      exposureMs: Int = 0
    ) {
      self.background = background
      self.flux = flux
      self.starRichness = starRichness
      self.noise = noise
      self.exposureMs = exposureMs
    }

    /// The brightness scalar that anchors the cycle.
    var level: Double { background + flux }
  }

  /// One light to classify, with its acquisition-order key.
  package struct Sample: Equatable, Sendable {
    package var order: Int
    package var path: String
    package var fingerprint: Fingerprint

    /// A sample.
    package init(order: Int, path: String, fingerprint: Fingerprint) {
      self.order = order
      self.path = path
      self.fingerprint = fingerprint
    }
  }

  /// The detected filter of one frame.
  package struct Assignment: Equatable, Sendable {
    package var path: String
    package var filter = ""
    package var runIndex: Int
    package var confidence = 0.0
    package var wheelTransition = false
    /// Relative background deviation of a flagged first frame.
    package var transitionDelta = 0.0
  }

  /// A contiguous same-filter run (one wheel dwell).
  package struct Run: Equatable, Sendable {
    package var filter: String
    package var paths: [String]
    package var confidence: Double
    package var count: Int { paths.count }
  }

  /// Everything detection found.
  package struct Result: Equatable, Sendable {
    package var order: [String]
    package var runs: [Run] = []
    package var assignments: [Assignment] = []
    package var overallConfidence = 0.0
  }

  /// Segmentation, assignment and transition thresholds.
  package struct Options: Equatable, Sendable {
    /// Stops at Ha on purpose: the signal cannot tell emission lines apart.
    package var order = ["L", "R", "G", "B", "Ha"]
    /// New run when the time gap exceeds this × the median gap.
    package var timeGapFactor = 4.0
    /// New run when the signal jump exceeds median + this × MAD of the jumps.
    package var breakSigma = 3.0
    /// Frames after the first that set a run's settled level.
    package var transitionLookahead = 4
    package var transitionRelativeFloor = 0.12
    package var transitionSigma = 3.0
    package var detectTransitions = true

    /// The robust defaults for block-captured deep-sky sequences.
    package init() {}
  }

  /// Orders the samples by acquisition, segments runs, labels each by the minimum-cost forward
  /// walk through the order, and flags unsettled first frames.
  package static func detect(_ samples: [Sample], options: Options = Options()) -> Result {
    var options = options
    if options.order.isEmpty { options.order = Options().order }
    guard !samples.isEmpty else { return Result(order: options.order) }
    let ordered = stableSorted(samples)
    let runs = segment(ordered, options: options)
    let labels = assignCyclic(ordered, runs: runs, order: options.order)
    var result = Result(order: options.order, overallConfidence: labels.overall)
    for (index, members) in runs.enumerated() {
      let paths = members.map { ordered[$0].path }
      result.runs.append(Run(filter: labels.filters[index], paths: paths, confidence: labels.confidence[index]))
      result.assignments += paths.map {
        Assignment(path: $0, filter: labels.filters[index], runIndex: index, confidence: labels.confidence[index])
      }
    }
    if options.detectTransitions { flagTransitions(ordered, runs: runs, into: &result.assignments, options: options) }
    return result
  }

  /// Runs of already-labeled samples, with only the transition flags (`FlagTransitions`).
  package static func flagTransitions(_ samples: [Sample], options: Options = Options()) -> [Assignment] {
    guard !samples.isEmpty else { return [] }
    let ordered = stableSorted(samples)
    let runs = segment(ordered, options: options)
    var assignments = runs.enumerated().flatMap { run, members in
      members.map { Assignment(path: ordered[$0].path, runIndex: run) }
    }
    flagTransitions(ordered, runs: runs, into: &assignments, options: options)
    return assignments
  }

  private static func stableSorted(_ samples: [Sample]) -> [Sample] {
    samples.enumerated()
      .sorted { $0.element.order != $1.element.order ? $0.element.order < $1.element.order : $0.offset < $1.offset }
      .map(\.element)
  }

  /// Marks a run's first frame when its background is off the settled level of the next few.
  private static func flagTransitions(
    _ samples: [Sample], runs: [[Int]], into assignments: inout [Assignment], options: Options
  ) {
    for members in runs where members.count >= options.transitionLookahead + 1 {
      let first = samples[members[0]]
      let reference = members[1...options.transitionLookahead].map { samples[$0].fingerprint.background }
      let (median, mad) = Robust.medianMAD(reference)
      guard median > 0 else { continue }
      let delta = abs(first.fingerprint.background - median)
      guard delta > max(options.transitionRelativeFloor * median, options.transitionSigma * mad),
        let index = assignments.firstIndex(where: { $0.path == first.path })
      else { continue }
      assignments[index].wheelTransition = true
      assignments[index].transitionDelta = delta / median
    }
  }

  /// Splits time-ordered samples where the exposure changes, the time gap is far above the
  /// cadence, or the signal jumps far above the frame-to-frame variation.
  static func segment(_ samples: [Sample], options: Options) -> [[Int]] {
    guard samples.count > 1 else { return samples.isEmpty ? [] : [[0]] }
    let pairs = zip(samples, samples.dropFirst())
    let gaps = pairs.map { Double($1.order - $0.order) }
    let jumps = pairs.map { abs($1.fingerprint.level - $0.fingerprint.level) }
    let medianGap = Robust.median(gaps)
    let (medianJump, madJump) = Robust.medianMAD(jumps)
    var runs: [[Int]] = []
    var current = [0]
    for index in 0..<samples.count - 1 {
      let breaks =
        samples[index].fingerprint.exposureMs != samples[index + 1].fingerprint.exposureMs
        || (medianGap > 0 && gaps[index] > options.timeGapFactor * medianGap)
        || (madJump > 0 && jumps[index] > medianJump + options.breakSigma * madJump)
      if breaks {
        runs.append(current)
        current = []
      }
      current.append(index + 1)
    }
    return runs + [current]
  }
}

/// The small robust statistics channel detection uses (upper-middle order statistics).
enum Robust {
  static func median(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.sorted()[values.count / 2]
  }

  static func medianMAD(_ values: [Double]) -> (median: Double, mad: Double) {
    guard !values.isEmpty else { return (0, 0) }
    let center = median(values)
    return (center, median(values.map { abs($0 - center) }))
  }

  /// Scales to [0, 1]; a flat slice maps to 0.5 (no information).
  static func minMaxNormalized(_ values: [Double]) -> [Double] {
    guard let low = values.min(), let high = values.max() else { return [] }
    let span = high - low
    return values.map { span > 0 ? ($0 - low) / span : 0.5 }
  }
}
