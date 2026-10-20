/// One distinct light configuration of a night, with its frame count.
package struct SessionConfig: Hashable, Sendable {
  package var filter: String
  package var exposureMs: Int
  package var gain: Int
  package var offset: Int
  package var bin: Int
  /// Rounded to the nearest 5 °C: a display label only, never a grouping key.
  package var tempBucketC: Int
  package var count = 0

  /// The light configurations of `night`, sorted by filter, exposure, gain (then the fields Go
  /// left to an unstable sort, so the order is deterministic).
  static func configs(_ frames: [CaptureFrame], night: String) -> [Self] {
    var counts: [Self: Int] = [:]
    for frame in frames where frame.type == .light && frame.session == night {
      let label = frame.hasTemp ? Int((frame.tempC / 5).rounded()) * 5 : 0
      let config = Self(
        filter: frame.filter, exposureMs: frame.exposureMs, gain: frame.gain,
        offset: frame.offset, bin: frame.binX, tempBucketC: label)
      counts[config, default: 0] += 1
    }
    return counts.map { config, count in
      var config = config
      config.count = count
      return config
    }
    .sorted { lhs, rhs in
      if lhs.filter != rhs.filter { return lhs.filter < rhs.filter }
      return [lhs.exposureMs, lhs.gain, lhs.offset, lhs.bin, -lhs.tempBucketC]
        .lexicographicallyPrecedes([
          rhs.exposureMs, rhs.gain, rhs.offset, rhs.bin, -rhs.tempBucketC,
        ])
    }
  }
}
