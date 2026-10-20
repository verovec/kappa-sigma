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
      found.append(Pixel(x: index % width, y: index / width, kind: kind, category: category, severity: severity))
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
      for (index, residual) in sigmaResiduals.enumerated() where Double(residual) / sigmaScale > Self.unstableK {
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
    let residuals = zip(values, baseline).map { $0 - $1 }
    let stride = residuals.count / statSample + 1
    let sample = Swift.stride(from: 0, to: residuals.count, by: stride).map { Double(residuals[$0]) }.sorted()
    guard !sample.isEmpty else { return (residuals, 0) }
    let median = sample[sample.count / 2]
    let deviations = sample.map { abs($0 - median) }.sorted()
    return (residuals, 1.4826 * deviations[deviations.count / 2])
  }

  /// A separable 5-median (rows, then columns), windows clamped at the borders.
  static func medianFilter5(_ values: [Float], width: Int, height: Int) -> [Float] {
    func pass(_ source: [Float], lines: Int, length: Int, index: (Int, Int) -> Int) -> [Float] {
      var out = [Float](repeating: 0, count: source.count)
      for line in 0..<lines {
        for position in 0..<length {
          let window = (max(0, position - 2)...min(length - 1, position + 2)).map { source[index(line, $0)] }.sorted()
          out[index(line, position)] = window[window.count / 2]
        }
      }
      return out
    }
    let rows = pass(values, lines: height, length: width) { $0 * width + $1 }
    return pass(rows, lines: width, length: height) { $1 * width + $0 }
  }
}
