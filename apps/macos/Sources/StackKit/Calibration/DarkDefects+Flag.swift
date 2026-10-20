internal import Accelerate
internal import Foundation

extension DarkDefects.Pixel {
  /// A listed pixel (hot `H` or cold `C`), for a list built by hand.
  package init(x: Int, y: Int, kind: Character) {
    self.init(x: x, y: y, kind: kind, category: kind == "C" ? "c" : "h", severity: 0)
  }
}

extension DarkDefects {
  /// Flags hot/cold from the mean map and unstable from the sigma map, caps, orders by (y, x).
  mutating func flag(means: [Float], sigmas: [Float]) {
    let width = self.width
    var found: [Pixel] = []
    var flagged = Set<Int>()
    func add(_ index: Int, _ kind: Character, _ category: Character, _ severity: Double) {
      guard flagged.insert(index).inserted else { return }
      found.append(
        Pixel(
          x: index % width, y: index / width, kind: kind, category: category, severity: severity))
    }
    let (meanResiduals, meanScale) = Self.localResiduals(means, width: width, height: height)
    if meanScale > 0 {
      for (index, residual) in meanResiduals.enumerated() {
        let deviation = Double(residual) / meanScale
        if deviation > Self.sigmaK {
          add(index, "H", "h", deviation)
        } else if deviation < -Self.sigmaK {
          add(index, "C", "c", -deviation)
        }
      }
    }
    let (sigmaResiduals, sigmaScale) = Self.localResiduals(sigmas, width: width, height: height)
    if sigmaScale > 0 {
      for (index, residual) in sigmaResiduals.enumerated()
      where Double(residual) / sigmaScale > Self.unstableK {
        add(index, "H", "u", Double(residual) / sigmaScale)
      }
    }
    let cap = Int(Self.maxFraction * Double(width) * Double(height))
    if cap >= 1, found.count > cap {
      found = Array(found.sorted { $0.severity > $1.severity }.prefix(cap))
      truncated = true
    }
    pixels = found.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
  }

  /// Each value minus its local baseline, and 1.4826 · MAD of a strided sample of the residuals.
  static func localResiduals(_ values: [Float], width: Int, height: Int) -> ([Float], Double) {
    let baseline = medianFilter5(values, width: width, height: height)
    let residuals = vDSP.subtract(values, baseline)
    let stride = residuals.count / statSample + 1
    let sample = Swift.stride(from: 0, to: residuals.count, by: stride).map {
      Double(residuals[$0])
    }.sorted()
    guard !sample.isEmpty else { return (residuals, 0) }
    let median = sample[sample.count / 2]
    let deviations = sample.map { abs($0 - median) }.sorted()
    return (residuals, 1.4826 * deviations[deviations.count / 2])
  }

  /// A separable 5-median (rows, then columns), windows clamped at the borders.
  package static func medianFilter5(_ values: [Float], width: Int, height: Int) -> [Float] {
    let rows = medianPass(values, lines: height, length: width, line: width, step: 1)
    return medianPass(rows, lines: width, length: height, line: 1, step: width)
  }

  /// One 5-median pass along lines of `length` samples `step` apart, lines `line` apart.
  ///
  /// The window is a reused 5-slot buffer sorted by insertion, in plain loops: no allocation, no
  /// generic iteration per pixel.
  private static func medianPass(
    _ source: [Float], lines: Int, length: Int, line: Int, step: Int
  ) -> [Float] {
    var out = [Float](repeating: 0, count: source.count)
    source.withUnsafeBufferPointer { source in
      out.withUnsafeMutableBufferPointer { out in
        withUnsafeTemporaryAllocation(of: Float.self, capacity: 5) { window in
          guard let source = source.baseAddress, let out = out.baseAddress,
            let window = window.baseAddress
          else { return }
          var lineIndex = 0
          while lineIndex < lines {
            median5(
              source + lineIndex * line, out + lineIndex * line, length: length, step: step,
              window: window)
            lineIndex += 1
          }
        }
      }
    }
    return out
  }

  /// The clamped 5-median of one line.
  private static func median5(
    _ source: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, length: Int, step: Int,
    window: UnsafeMutablePointer<Float>
  ) {
    var position = 0
    while position < length {
      var sample = max(0, position - 2)
      let high = min(length - 1, position + 2)
      var count = 0
      while sample <= high {
        let value = source[sample * step]
        var slot = count
        while slot > 0, window[slot - 1] > value {
          window[slot] = window[slot - 1]
          slot -= 1
        }
        window[slot] = value
        count += 1
        sample += 1
      }
      out[position * step] = window[count / 2]
      position += 1
    }
  }
}
