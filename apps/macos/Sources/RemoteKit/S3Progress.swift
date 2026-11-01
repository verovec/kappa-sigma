/// What a transfer reports while it runs.
package enum S3Progress: Sendable, Equatable {
  /// `bytes` of `total` moved so far; `total` is 0 when not known yet (a download without a
  /// listed size).
  case transferred(bytes: Int64, total: Int64)
  /// Try `attempt` failed with `reason` (a 5xx or a timeout); the next try follows the backoff.
  case retrying(attempt: Int, reason: String)
}

/// Receives progress; called from the transfer's task, so it must be cheap and thread-safe.
package typealias S3ProgressHandler = @Sendable (S3Progress) -> Void
