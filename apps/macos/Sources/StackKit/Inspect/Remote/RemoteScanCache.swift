package import Foundation

/// What the last scan of a remote prefix already read (card 0168), by object key: the ETag it was
/// read at, its size, the frame's header cards and the bytes of a side file.
///
/// A rescan lists the prefix again and reads only the keys whose ETag changed; a key the bucket no
/// longer holds leaves the cache with the listing. Nothing here is a verdict: pixel checks are
/// still not run on remote frames (`Inventory.notCheckedRemotely`), so a stale or missing cache
/// costs reads, never correctness. The body is kept by the project (`ProjectStore.setRemoteScan`).
///
/// Headers and side files only. The centred pixel runs a scan fetches are 200 000 values each
/// (`InventoryBuilder.statsSample`), which would make the body of one mono night hundreds of
/// megabytes of JSON in `project.db`; they are read again instead — one ranged request per frame,
/// as the first scan makes.
package struct RemoteScanCache: Codable, Sendable, Equatable {
  /// What was read of one object.
  package struct Entry: Codable, Sendable, Equatable {
    /// The ETag the bytes below were read at: the whole cache entry for a key is dropped when the
    /// bucket answers another one.
    package var etag: String
    /// Its size in bytes at that ETag.
    package var size: Int64
    /// The 80-character cards of a frame's primary header, `nil` when it is not a frame or its
    /// header could not be read.
    package var header: [String]?
    /// A side file's bytes (a sidecar, an `info.txt`), `nil` when the object is not one.
    package var contents: Data?

    /// An entry for an object of `etag` and `size` bytes, with what was read of it.
    package init(etag: String, size: Int64, header: [String]? = nil, contents: Data? = nil) {
      self.etag = etag
      self.size = size
      self.header = header
      self.contents = contents
    }
  }

  /// What was read, by object key (never by virtual path: the key is the bucket's own name for it).
  package var entries: [String: Entry]

  /// A cache holding `entries`.
  package init(entries: [String: Entry] = [:]) {
    self.entries = entries
  }

  /// Nothing read yet: every key is read.
  package static let empty = Self()

  /// What the scan listed of each object of `bucket`, by virtual path, in the stager's form
  /// (card 0181): the import sheet proves a bucket master with it, as the run will.
  package func identities(bucket: String) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: entries.map { key, entry in
        (
          RemoteSnapshot.path(bucket: bucket, key: key),
          FrameStager.identity(size: entry.size, etag: entry.etag)
        )
      })
  }

  /// A side file's bytes are kept only while they are sidecar-sized.
  ///
  /// A real SharpCap sidecar is a few KB, but `RemoteSnapshot.sideFileLimit` reads up to 1 MiB,
  /// and one per frame of a 348-pose night would put hundreds of megabytes through one
  /// `remote_scans` row.
  package static let maxCachedSideFileBytes = 64 << 10

  /// The cache a project kept, from its JSON body; a body this build cannot read throws, and the
  /// caller scans without a cache rather than refusing to scan.
  package init(json: Data) throws {
    self = try JSONDecoder().decode(Self.self, from: json)
  }

  /// This cache as the JSON body a project keeps (keys sorted: the same cache is the same bytes).
  package func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }
}
