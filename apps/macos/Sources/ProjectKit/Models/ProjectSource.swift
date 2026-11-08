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

  /// A source as the store reads it; tests build one to stand for a row (card 0154).
  package init(
    id: Int64, kind: Kind, path: String, readOnly: Bool, profileID: String? = nil,
    connectionID: String? = nil, bucket: String? = nil, prefix: String? = nil, createdAt: Int64,
    updatedAt: Int64
  ) {
    self.id = id
    self.kind = kind
    self.path = path
    self.readOnly = readOnly
    self.profileID = profileID
    self.connectionID = connectionID
    self.bucket = bucket
    self.prefix = prefix
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// The one spelling of a remote night's path, shared by the database and the scan:
  /// `s3://<bucket>/<prefix>` without a trailing `/`, `s3://<bucket>` for a whole bucket.
  package static func remotePath(bucket: String, prefix: String) -> String {
    let key = Self.key(prefix)
    return key.isEmpty ? "s3://" + bucket : "s3://" + bucket + "/" + key
  }

  /// The bucket and key a virtual path names, `nil` when the path is a file of this Mac.
  ///
  /// The inverse of `remotePath(bucket:prefix:)`: `s3://astro/M31/l.fits` is the key `M31/l.fits`
  /// of the bucket `astro`. A path with no key (the bucket's root) is no frame.
  package static func remoteParts(of path: String) -> (bucket: String, key: String)? {
    guard let folder = remoteFolder(of: path), !folder.prefix.isEmpty else { return nil }
    return (folder.bucket, folder.prefix)
  }

  /// The bucket and prefix a virtual path names, `""` for the bucket's root (`s3://astro`);
  /// `nil` when the path is a file of this Mac or names no bucket.
  package static func remoteFolder(of path: String) -> (bucket: String, prefix: String)? {
    let scheme = "s3://"
    guard path.hasPrefix(scheme) else { return nil }
    let parts = path.dropFirst(scheme.count)
      .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard let bucket = parts.first, !bucket.isEmpty else { return nil }
    return (String(bucket), parts.count > 1 ? String(parts[1]) : "")
  }

  /// The bucket and prefix a remote night reads its captures from (card 0180): its columns,
  /// else its virtual path, so a row written without them still names them; `nil` when local.
  package var remoteFolder: (bucket: String, prefix: String)? {
    guard kind == .remoteNight else { return nil }
    if let bucket, let prefix { return (bucket, prefix) }
    return Self.remoteFolder(of: path)
  }

  /// `prefix` as it is stored and as the scan lists it: without its trailing `/`, which a
  /// listing adds back and which therefore never makes a second source of one prefix.
  ///
  /// Nothing else is touched. `a//b` and `/M31` are legal S3 keys, and `Browse` hands prefixes
  /// straight back from the bucket's own `CommonPrefixes`: collapsing them would list — and scan
  /// — a prefix the user did not choose.
  package static func key(_ prefix: String) -> String {
    var key = Substring(prefix)
    while key.hasSuffix("/") { key = key.dropLast() }
    return String(key)
  }
}
