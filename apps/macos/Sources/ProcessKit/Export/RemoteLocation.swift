/// A place in an S3 bucket: the bucket and a key prefix read as folders (card 0152).
package struct RemoteLocation: Equatable, Sendable {
  /// The bucket name.
  package let bucket: String
  /// The key prefix, `/`-separated; leading and trailing slashes do not matter.
  package let prefix: String

  /// A bucket and a prefix.
  package init(bucket: String, prefix: String) {
    self.bucket = bucket
    self.prefix = prefix
  }

  /// The prefix as folder names, empty ones dropped: `/a//b/` is `["a", "b"]`.
  package var folders: [String] {
    prefix.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
  }

  /// Whether `self` is `other` or lies under it, folder by folder (`a/b-c` is not under `a/b`).
  package func isInside(_ other: Self) -> Bool {
    bucket == other.bucket && folders.starts(with: other.folders)
  }
}
