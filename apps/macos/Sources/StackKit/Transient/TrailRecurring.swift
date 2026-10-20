internal import Foundation

/// The coverage-aware mean residual (`meanAccum`): a frame counts at a pixel only where it has
/// data, so rotated zero-fill borders do not drag the mean negative. Float sums, as the legacy.
struct MeanResidual {
  var sum: [Float]
  var count: [UInt16]

  init(pixels: Int) {
    sum = [Float](repeating: 0, count: pixels)
    count = [UInt16](repeating: 0, count: pixels)
  }

  mutating func add(_ residual: [Float], frame: TrailMaskPlanes.Frame) {
    for index in residual.indices where !TrailMaskPlanes.isZero(frame, index) {
      sum[index] += residual[index]
      count[index] += 1
    }
  }

  /// The mean, 0 where no frame had data.
  var plane: [Float] {
    zip(sum, count).map { $1 > 0 ? $0 / Float($1) : 0 }
  }
}

/// A sky track several satellites reused (`transient/recurring.go`): too faint per frame, absent
/// from the median, but coherent in the mean residual, exactly as it would sum in the stack.
/// Each frame repairs only the windows it lights.
struct RecurringCorridor {
  var segment: TrailSegment
  var windows: [CorridorWindow]
  /// Per window, the fraction of basis frames lit there: the repair-mode switch.
  var shared: [Double]

  /// The mean-plane trails not already on the median's lines, with their shared fractions
  /// (`buildRecurring`).
  static func find(
    mean: [Float], medianSegments: [TrailSegment], residuals: [[Float]], skies: [Double],
    k: Double, size: (width: Int, height: Int)
  ) -> [Self] {
    TrailSegmentDetector.detect(mean, width: size.width, height: size.height, params: .residual(k: k))
      .filter { !coveredByMedian($0, medianSegments) }
      .map { segment in
        let windows = TrailCorridor.windows(segment, width: size.width, height: size.height)
        let shared = windows.map { window in
          window.pixels.isEmpty
            ? 0
            : TrailCorridor.witnessFraction(window, residuals: residuals, skies: skies, skip: -1)
              ?? 0
        }
        return Self(segment: segment, windows: windows, shared: shared)
      }
  }

  /// Whether `segment` runs along a median segment: normals within 2° (either sign), offsets
  /// within twice the wider swath.
  static func coveredByMedian(_ segment: TrailSegment, _ medianSegments: [TrailSegment]) -> Bool {
    let cosineTolerance = 0.9994
    return medianSegments.contains { other in
      var (dot, offset) = (segment.nx * other.nx + segment.ny * other.ny, other.c)
      if dot < 0 { (dot, offset) = (-dot, -offset) }
      return dot >= cosineTolerance
        && abs(segment.c - offset) <= 2 * max(segment.width, other.width)
    }
  }

  /// Repairs `frame` along the corridor (`maskFrameRecurring`): its lit windows ±1, from the
  /// median, or from the local sky where the basis shares the window (contaminated median).
  /// Mode changes inside a run are nudged open so no pixel is painted twice; `corridor` seeds the
  /// local-sky noise.
  func repair(
    _ frame: inout TrailMaskPlanes.Frame, own: [Float], sky: Double, median: [[Float]],
    corridor: Int, size: (width: Int, height: Int)
  ) -> Int {
    let lit = TrailCorridor.lit(windows, own: own, sky: sky) {
      TrailMaskPlanes.isZero(frame, $0)
    }
    guard !lit.windows.isEmpty, lit.pixels >= TrailCorridor.minimumPixels else { return 0 }
    var painted = 0
    for group in modeGroups(TrailCorridor.expanded(lit.windows, count: windows.count)) {
      var run = segment
      (run.t0, run.t1) = (windows[group.first].t0, windows[group.last].t1)
      if group.openEnd { run.t1 -= 1e-6 }
      for channel in frame.indices {
        painted +=
          group.localSky
          ? TrailSwath.paintLocalBackground(
            &frame[channel], width: size.width, height: size.height, segment: run,
            seed: TrailMaskPlanes.seed(segment: 1000 + corridor, channel: channel))
          : TrailSwath.paintMedian(
            &frame[channel], median: median[channel], width: size.width, height: size.height,
            segment: run)
      }
    }
    return painted
  }

  /// A run of consecutive windows sharing one repair mode; `openEnd` when the run continues in
  /// the other mode.
  struct Group: Equatable {
    var first: Int
    var last: Int
    var localSky: Bool
    var openEnd: Bool
  }

  /// Splits a sorted window list on gaps, then on repair-mode changes (`modeGroups`).
  func modeGroups(_ list: [Int]) -> [Group] {
    let local = { shared[$0] >= TrailCorridor.sharedRepairFraction }
    var out: [Group] = []
    var index = 0
    while index < list.count {
      var group = Group(first: list[index], last: list[index], localSky: local(list[index]), openEnd: false)
      var next = index + 1
      while next < list.count, list[next] == list[next - 1] + 1, local(list[next]) == group.localSky {
        group.last = list[next]
        next += 1
      }
      group.openEnd = next < list.count && list[next] == group.last + 1
      out.append(group)
      index = next
    }
    return out
  }
}
