internal import Foundation

/// What went wrong, with the service's own words kept as sent (R2: shown as is, never rewritten).
package enum S3Error: Error, Sendable, Equatable, CustomStringConvertible {
  /// The service answered non-2xx: its status, `<Code>`, `<Message>` and request id.
  case service(status: Int, code: String?, message: String?, requestID: String?)
  /// The endpoint URL is not `http(s)://host[:port]`.
  case invalidEndpoint(String)
  /// A request URL could not be built.
  case invalidRequest(String)
  /// The service answered 2xx with a body RemoteKit cannot read.
  case invalidResponse(String)
  /// A download's byte count differs from the expected size.
  case sizeMismatch(key: String, expected: Int64, actual: Int64)
  /// A download's content does not match its ETag (MD5) or `x-amz-checksum-sha256`.
  case checksumMismatch(key: String, expected: String, actual: String)
  /// The object's ETag changed since it was listed.
  case objectChanged(key: String, expectedETag: String, actualETag: String)
  /// The service's `answer` (a refused redirect, or a request signed for the wrong region) named
  /// `region` as the bucket's: either not the `connection`'s region, or one `host` does not serve.
  indirect case wrongRegion(
    bucket: String, region: String, connection: String, host: String, answer: Self)
  /// One request ran for `seconds`, the limit for a whole transfer; retrying would start over.
  case transferTimedOut(seconds: Double)
  /// `name` cannot be addressed on this endpoint, for `reason`; nothing was sent.
  case invalidBucket(name: String, reason: String)

  /// One line for the user, the S3 code and message verbatim.
  package var description: String {
    switch self {
    case .service(let status, let code, let message, _):
      "S3 \(status)" + (code.map { " \($0)" } ?? "") + (message.map { ": \($0)" } ?? "")
    case .invalidEndpoint(let url): "Not an S3 endpoint URL: \(url)"
    case .invalidRequest(let url): "Cannot build the request URL \(url)"
    case .invalidResponse(let what): "Unreadable S3 response: \(what)"
    case .sizeMismatch(let key, let expected, let actual):
      "\(key): \(actual) bytes received, \(expected) expected"
    case .checksumMismatch(let key, let expected, let actual):
      "\(key): checksum \(actual), \(expected) expected"
    case .objectChanged(let key, let expected, let actual):
      "\(key) changed on the server (ETag \(actual), \(expected) listed)"
    case .wrongRegion(let bucket, let region, let connection, let host, let answer):
      "\(answer.description) — bucket \(bucket) is in region \(region), "
        + (region.caseInsensitiveCompare(connection) == .orderedSame
          ? "which \(host) does not serve: use that region's endpoint"
          : "the connection says \(connection)")
    case .transferTimedOut(let seconds):
      "Transfer stopped after \(Self.duration(seconds)), the limit for one request"
    case .invalidBucket(let name, let reason): "Bucket name \"\(name)\": \(reason)"
    }
  }

  /// `seconds` in the largest whole unit: « 6 h », « 90 min », « 0.2 s ».
  static func duration(_ seconds: Double) -> String {
    if seconds >= 3600, seconds.truncatingRemainder(dividingBy: 3600) == 0 {
      return "\(Int(seconds / 3600)) h"
    }
    if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 {
      return "\(Int(seconds / 60)) min"
    }
    return seconds == seconds.rounded() ? "\(Int(seconds)) s" : "\(seconds) s"
  }

  /// The codes S3 documents as « try again », also sent inside a 200 (CompleteMultipartUpload).
  private static let transientCodes: Set<String> = [
    "InternalError", "ServiceUnavailable", "SlowDown",
  ]

  /// The 5xx answers that mean « later »; a 501 NotImplemented is permanent.
  /// 429 is throttling (R2, B2), not a client mistake: it is retried like a 503.
  private static let transientStatuses: Set<Int> = [429, 500, 502, 503, 504]

  /// Whether a new try may succeed: transient 5xx and 429, transient codes, S3's 400
  /// `RequestTimeout` (a timeout), and network timeouts; any other 4xx never.
  package static func isRetryable(_ error: any Error) -> Bool {
    switch error {
    case Self.service(let status, let code, _, _):
      transientStatuses.contains(status) || code == "RequestTimeout"
        || (status < 400 && transientCodes.contains(code ?? ""))
    case let error as URLError: [.timedOut, .networkConnectionLost].contains(error.code)
    default: false
    }
  }
}
