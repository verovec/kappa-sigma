/// Where a project's pixels come from, referenced by path and never written (R7).
package struct ProjectSource: Equatable, Sendable {
  /// What the path points to.
  package enum Kind: String, Sendable {
    /// An imported capture night (`~/Documents/astro/captures/…`).
    case night
    /// A legacy run folder (`~/Documents/astro/runs/…`).
    case legacyRun = "legacy_run"
    /// An S3 prefix read where it stands (card 0168): `path` is its virtual `s3://bucket/prefix`
    /// and its frames are never copied into the project.
    case remoteNight = "remote_night"
  }

  /// Row id.
  package let id: Int64
  /// What the path points to.
  package let kind: Kind
  /// Absolute path of the source folder, or the virtual `s3://bucket/prefix` of a remote night.
  package let path: String
  /// Always true today: the app never writes into a source.
  package let readOnly: Bool
  /// The profile kept when it was imported (card 0060), `nil` when none.
  package let profileID: String?
  /// The Settings connection (card 0150) a remote night is read through, `nil` when local.
  package let connectionID: String?
  /// The bucket of a remote night, `nil` when local.
  package let bucket: String?
  /// The prefix of a remote night, without its trailing `/` (`""` = the whole bucket), `nil`
  /// when local.
  package let prefix: String?
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64

  /// The one spelling of a remote night's path, shared by the database and the scan:
  /// `s3://<bucket>/<prefix>` without a trailing `/`, `s3://<bucket>` for a whole bucket.
  package static func remotePath(bucket: String, prefix: String) -> String {
    let key = Self.key(prefix)
    return key.isEmpty ? "s3://" + bucket : "s3://" + bucket + "/" + key
  }

  /// `prefix` as it is stored and as the scan lists it: the `/`-joined parts, so a leading,
  /// doubled or trailing slash never makes a second source of one prefix (the rule the app's
  /// `S3Target.key` already follows — an S3 key never begins with `/`).
  package static func key(_ prefix: String) -> String {
    prefix.split(separator: "/").joined(separator: "/")
  }
}
