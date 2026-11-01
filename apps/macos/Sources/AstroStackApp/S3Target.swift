package import Foundation

/// Where an export's S3 copy goes (card 0152): a connection of Settings › S3 connections (by id,
/// a rename follows), a bucket and a key prefix; the export's sub-path template follows it.
package nonisolated struct S3Target: Codable, Equatable, Sendable {
  /// The connection's id (`S3Connection.id`), never its name.
  package var connectionID: UUID
  /// The bucket the files go to.
  package var bucket: String
  /// The key prefix above the template's folders (`exports/`); empty = the bucket's root.
  package var prefix: String

  /// A target.
  package init(connectionID: UUID, bucket: String, prefix: String) {
    self.connectionID = connectionID
    self.bucket = bucket
    self.prefix = prefix
  }

  /// The target with its bucket and prefix trimmed (a pasted name often carries a space): the
  /// one shown, written and remembered.
  package var trimmed: Self {
    Self(
      connectionID: connectionID,
      bucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines),
      prefix: prefix.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// The `/`-joined key of `folders` under the prefix, without a trailing slash.
  package func key(_ folders: [String]) -> String {
    (prefix.split(separator: "/").map(String.init) + folders).joined(separator: "/")
  }

  /// `s3://bucket/key`, as shown and recorded.
  package func url(_ key: String) -> String {
    key.isEmpty ? "s3://\(bucket)" : "s3://\(bucket)/\(key)"
  }
}
