package import Foundation

/// A bucket the scan reads (card 0167), as two async closures: StackKit never imports RemoteKit,
/// the app adapts its `S3Client` (`list`, ranged `get`).
package struct RemoteObjectStore: Sendable {
  /// One stored object.
  package struct Object: Sendable, Equatable {
    /// Its full key.
    package let key: String
    /// Its size in bytes.
    package let size: Int64
    /// Its ETag (the scan cache keys on it, 0168).
    package let etag: String

    /// An object of `key`, `size` bytes, tagged `etag`.
    package init(key: String, size: Int64, etag: String) {
      self.key = key
      self.size = size
      self.etag = etag
    }
  }

  /// The bucket's name, the root of the virtual paths (`s3://<bucket>/<key>`).
  package let bucket: String
  /// Every object under a prefix.
  package let list: @Sendable (_ prefix: String) async throws -> [Object]
  /// The bytes of a key, or of an inclusive byte range of it.
  package let get: @Sendable (_ key: String, _ range: ClosedRange<Int64>?) async throws -> Data

  /// A store of `bucket` over the two closures.
  package init(
    bucket: String, list: @escaping @Sendable (String) async throws -> [Object],
    get: @escaping @Sendable (String, ClosedRange<Int64>?) async throws -> Data
  ) {
    self.bucket = bucket
    self.list = list
    self.get = get
  }
}
