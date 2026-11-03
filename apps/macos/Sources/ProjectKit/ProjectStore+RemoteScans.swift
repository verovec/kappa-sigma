package import Foundation

// MARK: - What a remote source's last scan already read (card 0168)

extension ProjectStore {
  /// The last scan answered for the remote source at `path` (`s3://bucket/prefix`), as the JSON
  /// body StackKit wrote (its `RemoteScanCache`); `nil` when the source was never scanned.
  ///
  /// Derived data: losing it costs reads, never correctness.
  package func remoteScan(of path: String) throws -> Data? {
    try body(named: path, in: .remoteScans)
  }

  /// Keeps `json` as the last scan of the remote source at `path`, replacing the one before it.
  package func setRemoteScan(_ json: Data, of path: String) throws {
    try save(json, named: path, in: .remoteScans)
  }

  /// Forgets the scan kept for the remote source at `path` (nothing when there is none): the next
  /// scan reads every key again.
  package func deleteRemoteScan(of path: String) throws {
    try delete(named: path, in: .remoteScans)
  }
}
