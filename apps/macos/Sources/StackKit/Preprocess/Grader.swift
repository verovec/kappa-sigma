internal import Foundation

/// Decides which registered subs are stacked (`internal/grade/grade.go`): absolute rules (trail,
/// roundness floor) per frame, relative rules (soft, sky glow, clouds, elongated vs the session)
/// against each span's robust statistics, and Siril's stack minimum restored globally.
package enum Grader {
  /// The rejection thresholds (`grade.Options`); `init()` is `DefaultOptions`.
  package struct Options: Equatable, Sendable {
    /// Always reject below this roundness (clearly trailed stars).
    package var roundnessFloor = 0.55
    /// Also reject below median − k·σ of the session's roundness.
    package var roundnessSigma = 2.5
    /// Reject above median + k·σ FWHM (soft frames).
    package var fwhmSigma = 2.5
    /// Reject above median + k·σ background (sky glow).
    package var backgroundSigma = 3.0
    /// Reject below this fraction of the median star count (clouds).
    package var starCountFraction = 0.5
    package var rejectTrails = true

    /// The legacy defaults.
    package init() {}
  }

  /// Robust rules need at least this many registered frames.
  static let minFramesForStats = 4
  /// A soft frame must also be this much worse than the median.
  static let minRelativeFWHM = 0.10
  /// The cloud rule needs a median of at least this many stars.
  static let minStarsForRule = 8.0
  /// `stack -filter-incl` needs two frames.
  static let stackMinimum = 2
  /// The reason prefix of a frame restored for the stack minimum.
  package static let keptStackMinimumPrefix = "kept (stack minimum) — was: "

  /// Grades in place; `spans` (positions in `grades`) scope the relative rules per capture night;
  /// empty means one population.
  package static func grade(
    _ grades: inout [FrameGrade], spans: [Range<Int>] = [], options: Options = Options()
  ) {
    for span in spans.isEmpty ? [0..<grades.count] : spans {
      let range = span.clamped(to: 0..<grades.count)
      guard !range.isEmpty else { continue }
      let stats = Statistics(grades[range])
      guard stats.registered > 0 else { continue }
      for index in range { reject(&grades[index], stats: stats, options: options) }
    }
    keepAtLeast(&grades, stackMinimum)
  }

  /// The 1-based indices to `unselect`.
  package static func rejectedIndices(_ grades: [FrameGrade]) -> [Int] {
    grades.filter(\.rejected).map(\.index)
  }

  /// Restores the sharpest rejected registered frames until `count` survive (capped by how many
  /// registered), keeping the original reason as provenance.
  package static func keepAtLeast(_ grades: inout [FrameGrade], _ count: Int) {
    let registered = grades.filter { $0.fwhm > 0 }
    var survivors = registered.count { !$0.rejected }
    while survivors < min(count, registered.count) {
      let candidates = grades.indices.filter { grades[$0].fwhm > 0 && grades[$0].rejected }
      guard let best = candidates.min(by: { grades[$0].fwhm < grades[$1].fwhm }) else { return }
      grades[best].rejected = false
      grades[best].rejectReason = keptStackMinimumPrefix + grades[best].rejectReason
      survivors += 1
    }
  }

  private static func reject(_ grade: inout FrameGrade, stats: Statistics, options: Options) {
    guard grade.fwhm > 0 else { return }
    var reasons: [String] = []
    if options.rejectTrails && grade.trailDetected {
      reasons.append("trail detected (score \(fixed(grade.trailScore)))")
    }
    if grade.roundness > 0 {
      if grade.roundness < options.roundnessFloor {
        let floor = fixed(options.roundnessFloor)
        reasons.append("trailed/elongated stars (roundness \(fixed(grade.roundness)) < \(floor))")
      } else if stats.registered >= minFramesForStats && stats.roundnessMAD > 0
        && grade.roundness < stats.roundnessMedian - options.roundnessSigma * stats.roundnessMAD
      {
        let median = fixed(stats.roundnessMedian)
        reasons.append(
          "elongated vs session (roundness \(fixed(grade.roundness)) < median \(median))")
      }
    }
    if stats.registered >= minFramesForStats {
      reasons += relativeReasons(grade, stats: stats, options: options)
    }
    guard !reasons.isEmpty else { return }
    grade.rejected = true
    grade.rejectReason = reasons.joined(separator: "; ")
  }

  private static func relativeReasons(_ grade: FrameGrade, stats: Statistics, options: Options)
    -> [String]
  {
    var reasons: [String] = []
    if stats.fwhmMedian > 0 && grade.fwhm > stats.fwhmMedian * (1 + minRelativeFWHM)
      && grade.fwhm > stats.fwhmMedian + options.fwhmSigma * stats.fwhmMAD
    {
      reasons.append("soft frame (FWHM \(fixed(grade.fwhm)) vs median \(fixed(stats.fwhmMedian)))")
    }
    if stats.backgroundMedian > 0 && stats.backgroundMAD > 0
      && grade.background > stats.backgroundMedian + options.backgroundSigma * stats.backgroundMAD
      && grade.background > 1.5 * stats.backgroundMedian
    {
      reasons.append("high sky background")
    }
    if stats.starMedian >= minStarsForRule
      && Double(grade.starCount) < options.starCountFraction * stats.starMedian
    {
      let median = String(format: "%.0f", stats.starMedian)
      reasons.append("few stars (\(grade.starCount) vs median \(median)) — likely clouds")
    }
    return reasons
  }

  private static func fixed(_ value: Double) -> String { String(format: "%.2f", value) }

  /// Median and σ (MAD × 1.4826) of a population's registered frames.
  struct Statistics {
    var registered = 0
    var fwhmMedian = 0.0
    var fwhmMAD = 0.0
    var backgroundMedian = 0.0
    var backgroundMAD = 0.0
    var roundnessMedian = 0.0
    var roundnessMAD = 0.0
    var starMedian = 0.0

    init(_ grades: ArraySlice<FrameGrade>) {
      let frames = grades.filter { $0.fwhm > 0 }
      registered = frames.count
      guard registered > 0 else { return }
      (fwhmMedian, fwhmMAD) = Self.sigma(frames.map(\.fwhm))
      (backgroundMedian, backgroundMAD) = Self.sigma(frames.map(\.background))
      (roundnessMedian, roundnessMAD) = Self.sigma(frames.map(\.roundness))
      starMedian = Robust.median(frames.map { Double($0.starCount) })
    }

    /// The upper median and the MAD scaled to σ.
    static func sigma(_ values: [Double]) -> (Double, Double) {
      let (median, mad) = Robust.medianMAD(values)
      return (median, 1.4826 * mad)
    }
  }
}
