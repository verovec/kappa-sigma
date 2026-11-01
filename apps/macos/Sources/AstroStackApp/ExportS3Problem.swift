/// Why an export's S3 side could not run, or did not finish (card 0152).
package nonisolated enum ExportS3Problem: Equatable, Sendable {
  /// Neither « on this Mac » nor « on S3 » is on.
  case noDestination
  /// The S3 target names no bucket.
  case noBucket
  /// The connection is gone from Settings, or has no secret.
  case connectionMissing
  /// The target is a capture bucket/prefix or under it (R7 on remote): the `s3://` URL.
  case captureBucket(String)
  /// The service answered an error before anything was written: its words, as sent.
  case service(String)
  /// The files are written here, their S3 copy failed: the service's words, as sent.
  case uploadFailed(String)
  /// « Resend to S3 » needs the export form's S3 connection.
  case resendNeedsConnection
}
