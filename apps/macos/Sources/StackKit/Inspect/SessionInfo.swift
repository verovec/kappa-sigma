/// One capture night of a scan (`inspect.SessionInfo`); key `""` is the undated bucket.
package struct SessionInfo: Equatable, Sendable {
  package var key: String
  package var startMs = 0
  package var endMs = 0
  package var counts: [FrameType: Int] = [:]
  package var configs: [SessionConfig] = []

  /// Per-night counts, time window and light configurations, sorted by night with the undated
  /// bucket last; empty when no frame carries a night.
  package static func summary(_ frames: [CaptureFrame]) -> [SessionInfo] {
    var nights: [String: SessionInfo] = [:]
    for frame in frames where frame.type != .video {
      var info = nights[frame.session] ?? SessionInfo(key: frame.session)
      info.counts[frame.type, default: 0] += 1
      if frame.dateObsMs > 0 {
        if info.startMs == 0 || frame.dateObsMs < info.startMs { info.startMs = frame.dateObsMs }
        info.endMs = max(info.endMs, frame.dateObsMs)
      }
      nights[frame.session] = info
    }
    guard !(nights.isEmpty || (nights.count == 1 && nights[""] != nil)) else { return [] }
    return nights.values
      .map { info in
        var info = info
        info.configs = SessionConfig.configs(frames, night: info.key)
        return info
      }
      .sorted { lhs, rhs in
        lhs.key.isEmpty != rhs.key.isEmpty ? rhs.key.isEmpty : lhs.key < rhs.key
      }
  }
}

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
  static func configs(_ frames: [CaptureFrame], night: String) -> [SessionConfig] {
    var counts: [SessionConfig: Int] = [:]
    for frame in frames where frame.type == .light && frame.session == night {
      let label = frame.hasTemp ? Int((frame.tempC / 5).rounded()) * 5 : 0
      let config = SessionConfig(
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
        .lexicographicallyPrecedes([rhs.exposureMs, rhs.gain, rhs.offset, rhs.bin, -rhs.tempBucketC])
    }
  }
}
