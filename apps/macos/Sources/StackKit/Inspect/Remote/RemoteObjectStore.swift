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
  /// Writes a whole key to a file, verified, leaving nothing behind when it fails (card 0154);
  /// `nil` for a store that has only `get` (the in-memory ones of the tests).
  let fetch: (@Sendable (_ key: String, _ destination: URL) async throws -> Object)?

  /// A store of `bucket` over the two closures, and the file download when it has one.
  package init(
    bucket: String, list: @escaping @Sendable (String) async throws -> [Object],
    get: @escaping @Sendable (String, ClosedRange<Int64>?) async throws -> Data,
    fetch: (@Sendable (String, URL) async throws -> Object)? = nil
  ) {
    self.bucket = bucket
    self.list = list
    self.get = get
    self.fetch = fetch
  }

  /// Writes `key` to `destination` and says what was written.
  ///
  /// The store's own download when it has one (ranged, verified, atomic); otherwise `get`
  /// written out, which is what an in-memory store can do. Nothing is left behind on failure.
  package func download(_ key: String, to destination: URL) async throws -> Object {
    if let fetch { return try await fetch(key, destination) }
    let part = destination.appendingPathExtension("part")
    try? FileManager.default.removeItem(at: part)
    do {
      let bytes = try await get(key, nil)
      try bytes.write(to: part, options: .atomic)
      try FileManager.default.moveItem(at: part, to: destination)
      return Object(key: key, size: Int64(bytes.count), etag: "")
    } catch {
      try? FileManager.default.removeItem(at: part)
      throw error
    }
  }
}
