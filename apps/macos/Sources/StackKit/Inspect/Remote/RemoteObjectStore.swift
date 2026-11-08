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

    /// What identifies it (`size|etag`): what a master's `.sig` and a lane's digest sign for a
    /// frame of a bucket, and what a later listing is compared with (card 0181).
    package var identity: String { Self.identity(size: size, etag: etag) }

    /// The identity of an object of `size` bytes tagged `etag`.
    package static func identity(size: Int64, etag: String) -> String { "\(size)|\(etag)" }

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
  /// Whether a read's failure is the bucket's, for every object (card 0186).
  ///
  /// A key that may list but not read, a service or network down: the scan stops (R2, never an
  /// empty « successful » scan). An object gone or shrunk since the listing is that frame's skip.
  /// StackKit cannot read the client's errors itself: the store says which is which.
  package let failsTheScan: @Sendable (any Error) -> Bool

  /// A store of `bucket` over the two closures, the file download when it has one, and how to
  /// tell a failure of the bucket from one of an object (`false`: every failure is the object's).
  package init(
    bucket: String, list: @escaping @Sendable (String) async throws -> [Object],
    get: @escaping @Sendable (String, ClosedRange<Int64>?) async throws -> Data,
    fetch: (@Sendable (String, URL) async throws -> Object)? = nil,
    failsTheScan: @escaping @Sendable (any Error) -> Bool = { _ in false }
  ) {
    self.bucket = bucket
    self.list = list
    self.get = get
    self.fetch = fetch
    self.failsTheScan = failsTheScan
  }

  /// Writes `key` to `destination` and says what was written.
  ///
  /// The store's own download when it has one (ranged, verified, atomic); otherwise `get`
  /// written out, which is what an in-memory store can do. Nothing is left behind on failure.
  /// `expecting` is the identity a run listed (card 0186): bytes that are not that object any
  /// more (uploaded again since) are removed and refused — a lane never stacks what it did not
  /// list.
  package func download(_ key: String, to destination: URL, expecting identity: String? = nil)
    async throws -> Object
  {
    let object = try await written(key, to: destination)
    guard let identity, !Self.object(object, matches: identity) else { return object }
    try? FileManager.default.removeItem(at: destination)
    throw Changed(key: key, listed: identity, read: object.identity)
  }

  /// Whether `object` is the one listed as `identity`: its size and ETag, or its size alone
  /// when either side has no ETag (an in-memory store, a listing or gateway that drops them).
  static func object(_ object: Object, matches identity: String) -> Bool {
    let size = Object.identity(size: object.size, etag: "")
    guard !object.etag.isEmpty, !identity.hasSuffix("|") else { return identity.hasPrefix(size) }
    return object.identity == identity
  }

  /// `error` in a sentence: a network error's own description, else what it says of itself
  /// (an S3 answer's code and message as sent).
  package static func words(of error: any Error) -> String {
    (error as NSError).domain == NSURLErrorDomain
      ? error.localizedDescription : String(describing: error)
  }

  /// A key whose bytes are no longer the object a run listed.
  package struct Changed: Error, Equatable, CustomStringConvertible {
    /// The key.
    package let key: String
    /// `size|etag` as the run listed it.
    package let listed: String
    /// `size|etag` as the download read it.
    package let read: String

    /// One line naming both.
    package var description: String {
      "\(key) changed since this run listed it (\(read), \(listed) listed)"
    }
  }

  /// `key` written to `destination` by the store's download, or by `get`.
  private func written(_ key: String, to destination: URL) async throws -> Object {
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
