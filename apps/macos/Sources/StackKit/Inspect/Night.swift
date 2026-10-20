package import Foundation

/// Capture-night sessionization (`internal/inspect/session.go`): a dated frame belongs to the
/// observing night it STARTED, bucketed at local noon, so an after-midnight sub joins its evening.
package enum Night {
  /// The night key (`YYYY-MM-DD`) of an epoch-ms instant in `timeZone`; `""` when `ms <= 0`.
  package static func key(ms: Int, in timeZone: TimeZone) -> String {
    guard ms > 0 else { return "" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let instant = Date(timeIntervalSince1970: Double(ms) / 1000 - 12 * 3600)
    let day = calendar.dateComponents([.year, .month, .day], from: instant)
    guard let year = day.year, let month = day.month, let date = day.day else { return "" }
    return String(format: "%04d-%02d-%02d", year, month, date)
  }

  /// Whether lights and flats span at least two KNOWN nights; undated strays never split a scan.
  package static func spansSeveral(_ frames: [CaptureFrame]) -> Bool {
    var first = ""
    for frame in frames where !frame.session.isEmpty && [.light, .flat].contains(frame.type) {
      if first.isEmpty {
        first = frame.session
      } else if frame.session != first {
        return true
      }
    }
    return false
  }
}
