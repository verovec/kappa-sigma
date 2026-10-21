/// CPU oracles of the grey morphology `GreyMorphology` runs on the GPU.
///
/// `vanHerk` is the van Herk / Gil-Werman running min/max (O(1) per pixel, blocks of 2r + 1);
/// `naive` is astrocomp's `sepFilter` (the window clipped to the image at the edges). Both must
/// agree, so the GPU is pinned against an independent algorithm, not a transcription of itself.
enum MorphologyOracle {
  /// Grey opening (erosion then dilation) of a `width` × `height` plane with a square of side
  /// 2·radius + 1.
  static func opening(
    _ plane: [Float], width: Int, height: Int, radius: Int,
    filter: ([Float], Int, Bool) -> [Float] = vanHerk
  ) -> [Float] {
    let eroded = separable(
      plane, width: width, height: height, radius: radius, isMax: false, filter)
    return separable(eroded, width: width, height: height, radius: radius, isMax: true, filter)
  }

  /// One erosion or dilation: rows then columns.
  static func separable(
    _ plane: [Float], width: Int, height: Int, radius: Int, isMax: Bool,
    _ filter: ([Float], Int, Bool) -> [Float]
  ) -> [Float] {
    var rows = plane
    for y in 0..<height {
      let line = Array(plane[(y * width)..<((y + 1) * width)])
      rows.replaceSubrange((y * width)..<((y + 1) * width), with: filter(line, radius, isMax))
    }
    var out = rows
    for x in 0..<width {
      let column = (0..<height).map { rows[$0 * width + x] }
      for (y, value) in filter(column, radius, isMax).enumerated() { out[y * width + x] = value }
    }
    return out
  }

  /// van Herk / Gil-Werman: per block of k = 2r + 1, prefix and suffix extrema; the window
  /// [i − r, i + r] is then suffix[i − r] ⊕ prefix[i + r]. Padding with the neutral element
  /// (+∞ for min, −∞ for max) clips the window to the line, like astrocomp.
  static func vanHerk(_ line: [Float], radius: Int, isMax: Bool) -> [Float] {
    guard radius > 0, !line.isEmpty else { return line }
    let k = 2 * radius + 1
    let neutral: Float = isMax ? -.infinity : .infinity
    let pick: (Float, Float) -> Float = isMax ? { max($0, $1) } : { min($0, $1) }
    let blocks = (line.count + 2 * radius + k - 1) / k
    var padded = [Float](repeating: neutral, count: blocks * k)
    padded.replaceSubrange(radius..<(radius + line.count), with: line)
    var prefix = padded
    var suffix = padded
    for start in stride(from: 0, to: padded.count, by: k) {
      for i in (start + 1)..<(start + k) { prefix[i] = pick(prefix[i - 1], padded[i]) }
      for i in stride(from: start + k - 2, through: start, by: -1) {
        suffix[i] = pick(suffix[i + 1], padded[i])
      }
    }
    // Output i (padded index i + r) covers padded [i, i + 2r].
    return (0..<line.count).map { pick(suffix[$0], prefix[$0 + 2 * radius]) }
  }

  /// astrocomp's `sepFilter` along one line.
  static func naive(_ line: [Float], radius: Int, isMax: Bool) -> [Float] {
    line.indices.map { index in
      let window = line[max(index - radius, 0)...min(index + radius, line.count - 1)]
      return (isMax ? window.max() : window.min()) ?? line[index]
    }
  }
}
