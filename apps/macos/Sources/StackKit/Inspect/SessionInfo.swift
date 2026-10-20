/// One capture night of a scan (`inspect.SessionInfo`); key `""` is the undated bucket.
package struct SessionInfo: Equatable, Sendable {
  package var key: String
  package var startMs = 0
  package var endMs = 0
  package var counts: [FrameType: Int] = [:]
  package var configs: [SessionConfig] = []

  /// Per-night counts, time window and light configurations, sorted by night with the undated
  /// bucket last; empty when no frame carries a night.
  package static func summary(_ frames: [CaptureFrame]) -> [Self] {
    var nights: [String: Self] = [:]
    for frame in frames where frame.type != .video {
      var info = nights[frame.session] ?? Self(key: frame.session)
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
