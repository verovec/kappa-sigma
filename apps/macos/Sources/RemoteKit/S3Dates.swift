package import Foundation

/// The two date forms S3 writes.
package enum S3Dates {
  /// `2026-10-18T21:04:05.123Z` (listings), with or without fractional seconds.
  package static func iso8601(_ text: String) -> Date? {
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
      ?? (try? Date.ISO8601FormatStyle().parse(text))
  }

  /// `Sun, 18 Oct 2026 21:04:05 GMT` (the `Last-Modified` header).
  package static func http(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: text)
  }
}
