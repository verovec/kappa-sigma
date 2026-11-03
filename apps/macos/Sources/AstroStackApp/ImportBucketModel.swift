package import Foundation
internal import Observation

/// The « Bucket S3 » half of the Import sheet (card 0169): which connection, which bucket, and
/// where in it — browsed one level at a time (`delimiter=/`), never by listing the whole bucket.
///
/// A listing that fails keeps the folders already shown and says why: an empty list would read as
/// « this prefix holds nothing », which is a verdict nobody measured (R2).
@Observable
package final class ImportBucketModel {
  /// Lists the sub-prefixes of one level, as `S3Client.list(bucket:prefix:delimiter:)` answers
  /// them (full prefixes, each ending in `/`).
  package typealias Browsing =
    @Sendable (_ connection: UUID, _ bucket: String, _ prefix: String) async throws -> [String]

  /// The connections of Settings › S3 connections, in their stored order.
  package let connections: [S3Connection]
  /// The connection chosen, `nil` until the user picks one; changing it starts over, since the
  /// level browsed belongs to the bucket it was listed in.
  package var connectionID: UUID? {
    didSet { if connectionID != oldValue { startOver() } }
  }
  /// The bucket's name, as typed; changing it starts over.
  package var bucket = "" {
    didSet { if bucket != oldValue { startOver() } }
  }
  /// Where in the bucket the browse stands (`""` = its root).
  package private(set) var prefix = ""
  /// The sub-prefixes of `prefix`, as the last successful listing answered them.
  package private(set) var folders: [String] = []
  /// Whether a level was ever listed: before that, « no folder » is not something anyone read.
  package private(set) var hasListed = false
  /// Whether a listing is in flight.
  package private(set) var isBrowsing = false
  /// Why the last listing failed, `nil` once one succeeds.
  package private(set) var error: UserFacingError?

  private let browsing: Browsing
  private var listing: Task<Void, Never>?

  /// A model over `connections`, listing through `browsing`.
  package init(connections: [S3Connection], browsing: @escaping Browsing) {
    self.connections = connections
    self.browsing = browsing
  }

  /// What the Import sheet would scan: `nil` until a connection and a bucket are both chosen.
  package var target: RemoteImportTarget? {
    let name = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let connectionID, !name.isEmpty else { return nil }
    return RemoteImportTarget(connectionID: connectionID, bucket: name, prefix: prefix)
  }

  /// The prefix one level up, `nil` at the bucket's root.
  package var parent: String? {
    guard !prefix.isEmpty else { return nil }
    let parts = prefix.split(separator: "/").dropLast()
    return parts.isEmpty ? "" : parts.joined(separator: "/") + "/"
  }

  /// Lists the current prefix; a listing already running is replaced.
  package func browse() {
    guard let target else { return }
    listing?.cancel()
    isBrowsing = true
    let browsing = self.browsing
    listing = Task { [prefix] in
      do {
        let folders = try await browsing(target.connectionID, target.bucket, prefix)
        guard !Task.isCancelled else { return }
        self.folders = folders
        hasListed = true
        error = nil
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        // The folders of the level that did answer stay on screen.
        self.error = UserFacingError(error)
      }
      isBrowsing = false
    }
  }

  /// Goes down into `folder` (a full prefix of `folders`) and lists it.
  package func enter(_ folder: String) {
    prefix = folder
    browse()
  }

  /// Goes back up one level and lists it (nothing at the root).
  package func up() {
    guard let parent else { return }
    prefix = parent
    browse()
  }

  /// Waits for the listing in flight, if any.
  package func settled() async {
    await listing?.value
  }

  /// Back to the root of a freshly named bucket: the level listed in the previous one says
  /// nothing about this one, and claiming it does would be a verdict nobody read (R2).
  private func startOver() {
    listing?.cancel()
    listing = nil
    isBrowsing = false
    prefix = ""
    folders = []
    hasListed = false
    error = nil
  }
}
