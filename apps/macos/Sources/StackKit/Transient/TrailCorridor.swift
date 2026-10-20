internal import Foundation

/// One 64-step stretch of a segment's swath (`corridorWindow`): the unique plane indices inside
/// the swath over t ∈ [t0, t1].
struct CorridorWindow {
  var t0: Double
  var t1: Double
  var pixels: [Int] = []
}

/// The windowed validation of a line candidate (`transient/corridor.go`, `validTrailBasis`).
///
/// A real trail lights its corridor in one frame, or each stretch of a reused track in a few;
/// walking noise lights the same stretches in a large fraction of frames. Candidate and
/// witnesses are compared window by window.
enum TrailCorridor {
  /// Median lit-window witness fraction at or above this: fixed pattern.
  static let fixedPatternFraction = 0.30
  /// Corridor significance at half the per-pixel k, to catch the faint wings.
  static let wingK = 0.5
  /// Fewer lit corridor pixels than this: not a real trail extent.
  static let minimumPixels = 24
  static let windowLength = 64.0
  /// A window needs this many non-zero pixels to be judged.
  static let windowMinimumPixels = 32
  /// Observing witnesses a window's fraction needs (four witnesses in a minimal five-frame run).
  static let minimumWitnesses = 3
  /// A recurring window lit in this fraction of the basis has a contaminated median.
  static let sharedRepairFraction = 0.45

  /// The segment's swath in windows along the line, ⊥ steps up to ±width (`corridorWindows`).
  static func windows(_ segment: TrailSegment, width: Int, height: Int) -> [CorridorWindow] {
    let count = Int((segment.t1 - segment.t0) / windowLength) + 1
    var windows = (0..<count).map { bucket in
      CorridorWindow(
        t0: segment.t0 + Double(bucket) * windowLength,
        t1: min(segment.t1, segment.t0 + Double(bucket + 1) * windowLength))
    }
    var seen = Set<Int>()
    let (px, py) = (segment.nx * segment.c, segment.ny * segment.c)
    var t = segment.t0
    while t <= segment.t1 {
      let bucket = min(Int((t - segment.t0) / windowLength), count - 1)
      let (bx, by) = (px - t * segment.ny, py + t * segment.nx)
      var offset = -segment.width
      while offset <= segment.width {
        let x = Int((bx + offset * segment.nx).rounded())
        let y = Int((by + offset * segment.ny).rounded())
        if x >= 0, x < width, y >= 0, y < height, seen.insert(y * width + x).inserted {
          windows[bucket].pixels.append(y * width + x)
        }
        offset += 1
      }
      t += 1
    }
    return windows
  }

  /// The windows where the frame's own residual is significant (mean ≥ wingK·sky over ≥ 32
  /// non-zero pixels) and their pixel total (`litWindows`).
  static func lit(
    _ windows: [CorridorWindow], own: [Float], sky: Double, isZero: (Int) -> Bool
  ) -> (windows: [Int], pixels: Int) {
    var (lit, pixels) = ([Int](), 0)
    for (bucket, window) in windows.enumerated() {
      var (sum, count) = (0.0, 0)
      for pixel in window.pixels where !isZero(pixel) {
        sum += Double(own[pixel])
        count += 1
      }
      guard count >= windowMinimumPixels, sum / Double(count) >= wingK * sky else { continue }
      lit.append(bucket)
      pixels += count
    }
    return (lit, pixels)
  }

  /// The fraction of observing witnesses lit over one window (`witnessWindowFrac`); a witness
  /// below −3σ there has no data (zero fill reads −median). Nil under three observers.
  static func witnessFraction(
    _ window: CorridorWindow, residuals: [[Float]], skies: [Double], skip: Int
  ) -> Double? {
    var (lit, observing) = (0, 0)
    for (witness, residual) in residuals.enumerated() where witness != skip {
      var sum = 0.0
      for pixel in window.pixels { sum += Double(residual[pixel]) }
      let mean = sum / Double(window.pixels.count)
      guard mean >= -3 * skies[witness] else { continue }
      observing += 1
      if mean >= wingK * skies[witness] { lit += 1 }
    }
    return observing < minimumWitnesses ? nil : Double(lit) / Double(observing)
  }

  /// The median, over the lit windows, of the witness fraction (`fixedPatternFrac`); nil when no
  /// lit window had enough observers.
  static func recurrence(
    _ windows: [CorridorWindow], lit: [Int], residuals: [[Float]], skies: [Double], skip: Int
  ) -> Double? {
    let fractions = lit.filter { !windows[$0].pixels.isEmpty }.compactMap {
      witnessFraction(windows[$0], residuals: residuals, skies: skies, skip: skip)
    }.sorted()
    return fractions.isEmpty ? nil : fractions[fractions.count / 2]
  }

  /// The candidate's lit runs to paint when it is a real trail, nil when it is walking noise or
  /// cannot be judged (`validTrailBasis`). `skip` is the frame's own index in the basis, or −1.
  static func validate(
    _ segment: TrailSegment, own: [Float], sky: Double, residuals: [[Float]], skies: [Double],
    skip: Int, size: (width: Int, height: Int), isZero: (Int) -> Bool
  ) -> [TrailSegment]? {
    let windows = windows(segment, width: size.width, height: size.height)
    let lit = lit(windows, own: own, sky: sky, isZero: isZero)
    guard !lit.windows.isEmpty, lit.pixels >= minimumPixels,
      let fraction = recurrence(
        windows, lit: lit.windows, residuals: residuals, skies: skies, skip: skip),
      fraction < fixedPatternFraction
    else { return nil }
    return runs(segment, windows: windows, lit: lit.windows)
  }

  /// The lit windows ±1, merged into disjoint runs, as extent-clipped copies of the segment
  /// (`paintRuns`): only where the frame carries the streak is painted.
  static func runs(_ segment: TrailSegment, windows: [CorridorWindow], lit: [Int]) -> [TrailSegment]
  {
    groups(expanded(lit, count: windows.count)).map { first, last in
      var run = segment
      (run.t0, run.t1) = (windows[first].t0, windows[last].t1)
      return run
    }
  }

  /// The windows ±1 (wing margin), sorted and unique (`expandLit`).
  static func expanded(_ lit: [Int], count: Int) -> [Int] {
    Set(lit.flatMap { [$0 - 1, $0, $0 + 1] }).filter { $0 >= 0 && $0 < count }.sorted()
  }

  /// Consecutive runs of a sorted window list, as (first, last).
  static func groups(_ windows: [Int]) -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    for window in windows {
      if let last = out.last, last.1 + 1 == window {
        out[out.count - 1].1 = window
      } else {
        out.append((window, window))
      }
    }
    return out
  }
}
