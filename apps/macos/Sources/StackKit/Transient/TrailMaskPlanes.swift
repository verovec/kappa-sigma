internal import Accelerate
internal import Foundation

/// The cross-frame statistics of the trail mask (`transient/planes.go`, the blanket pass and
/// `residualSky`).
///
/// A frame is its planes, `frame[channel][pixel]`.
enum TrailMaskPlanes {
  typealias Frame = [[Float]]

  /// Per channel, the per-pixel median and 1.4826·MAD across `frames` (double arithmetic, the
  /// median averaging the two middle values), computed in row bands concurrently.
  @concurrent
  static func medianSigma(_ frames: [Frame], channels: Int, pixels: Int) async -> (
    median: [[Float]], sigma: [[Float]]
  ) {
    var (median, sigma) = ([[Float]](), [[Float]]())
    let bandSize = max(4096, pixels / max(1, ProcessInfo.processInfo.activeProcessorCount * 4))
    for channel in 0..<channels {
      let bands = await withTaskGroup(of: (Int, [Float], [Float]).self) { group in
        for start in stride(from: 0, to: pixels, by: bandSize) {
          group.addTask {
            let range = start..<min(start + bandSize, pixels)
            let (band, spread) = Self.band(frames, channel: channel, range: range)
            return (start, band, spread)
          }
        }
        var bands: [(Int, [Float], [Float])] = []
        for await band in group { bands.append(band) }
        return bands.sorted { $0.0 < $1.0 }
      }
      median.append(bands.flatMap(\.1))
      sigma.append(bands.flatMap(\.2))
    }
    return (median, sigma)
  }

  /// One band of `medianSigma`.
  private static func band(_ frames: [Frame], channel: Int, range: Range<Int>) -> (
    [Float], [Float]
  ) {
    var column = [Double](repeating: 0, count: frames.count)
    var deviations = column
    var (median, sigma) = ([Float](), [Float]())
    median.reserveCapacity(range.count)
    sigma.reserveCapacity(range.count)
    for pixel in range {
      // A cancelled run stops between rows; the caller checks right after the pass.
      if pixel % 65_536 == 0 && Task.isCancelled { break }
      for index in frames.indices { column[index] = Double(frames[index][channel][pixel]) }
      let center = sortedMedian(&column)
      for index in column.indices { deviations[index] = abs(column[index] - center) }
      median.append(Float(center))
      sigma.append(Float(1.4826 * sortedMedian(&deviations)))
    }
    return (median, sigma)
  }

  /// Sorts `values` and returns their median, the two middle values averaged (`median`).
  static func sortedMedian(_ values: inout [Double]) -> Double {
    vDSP.sort(&values, sortOrder: .ascending)
    let middle = values.count / 2
    return values.count % 2 == 1 ? values[middle] : 0.5 * (values[middle - 1] + values[middle])
  }

  /// The per-pixel maximum of the channel medians: a geostationary streak is caught whichever
  /// channel it is brightest in.
  static func maxMedian(_ median: [[Float]]) -> [Float] {
    guard var out = median.first else { return [] }
    for plane in median.dropFirst() {
      for index in out.indices where plane[index] > out[index] { out[index] = plane[index] }
    }
    return out
  }

  /// Streaks in the median itself (same sky pixels in most frames), raw-mode detection.
  static func medianTrails(_ median: [[Float]], width: Int, height: Int) -> [TrailSegment] {
    TrailSegmentDetector.detect(
      maxMedian(median), width: width, height: height, params: .raw(k: 0))
  }

  /// The frame's signed residual over the median, the most positive channel kept: the sky noise
  /// survives (a clipped plane has a zero MAD) and a one-frame streak stands far above it.
  static func residual(_ frame: Frame, median: [[Float]]) -> [Float] {
    var out = zip(frame[0], median[0]).map { $0 - $1 }
    for channel in frame.indices.dropFirst() {
      for index in out.indices {
        let difference = frame[channel][index] - median[channel][index]
        if difference > out[index] { out[index] = difference }
      }
    }
    return out
  }

  /// A residual plane's robust sky noise, 1.4826·MAD on a ≤ 200 000-sample stride (the median
  /// averaged, the MAD the upper middle deviation).
  static func residualSky(_ plane: [Float]) -> Double {
    guard !plane.isEmpty else { return 0 }
    let step = plane.count > 200_000 ? plane.count / 200_000 : 1
    var samples = stride(from: 0, to: plane.count, by: step).map { Double(plane[$0]) }
    let center = sortedMedian(&samples)
    var deviations = samples.map { abs($0 - center) }
    vDSP.sort(&deviations, sortOrder: .ascending)
    return 1.4826 * deviations[deviations.count / 2]
  }

  /// Replaces every pixel above median + k·σ with the median (cosmic rays, hot pixels, a trail's
  /// core); returns the count.
  static func blanket(_ frame: inout Frame, median: [[Float]], sigma: [[Float]], k: Double) -> Int {
    var count = 0
    for channel in frame.indices {
      let (center, spread) = (median[channel], sigma[channel])
      for index in frame[channel].indices where spread[index] > 0 {
        if Double(frame[channel][index]) > Double(center[index]) + k * Double(spread[index]) {
          frame[channel][index] = center[index]
          count += 1
        }
      }
    }
    return count
  }

  /// Whether pixel `index` is Siril's registration fill (every channel exactly 0).
  static func isZero(_ frame: Frame, _ index: Int) -> Bool {
    frame.allSatisfy { $0[index] == 0 }
  }

  /// A stable per-(segment, channel) seed for the local-sky fill.
  static func seed(segment: Int, channel: Int) -> UInt64 {
    UInt64(segment + 1) * 2_000_003 + UInt64(channel) * 131
  }
}
