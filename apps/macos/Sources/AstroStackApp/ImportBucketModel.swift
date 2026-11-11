package import Foundation
internal import Observation

/// The « Bucket S3 » half of the Import sheet (card 0169): which connection, which bucket, and
/// where in it — browsed one level at a time (`delimiter=/`), never by listing the whole bucket.
///
/// A listing that fails keeps the folders already shown and says why: an empty list would read as
/// « this prefix holds nothing », which is a verdict nobody measured (R2).
@Observable
package final class ImportBucketModel {
  /// Lists the sub-prefixes of one level, as `S3Client.listPrefixes(bucket:prefix:delimiter:)`
  /// answers them (full prefixes, each ending in `/`).
  package typealias Browsing =
    @Sendable (_ connection: UUID, _ bucket: String, _ prefix: String) async throws -> [String]

  /// The connections of Settings › S3 connections, in their stored order, as last read.
  package private(set) var connections: [S3Connection]
  /// The connection chosen, `nil` until the user picks one; changing it starts over, since the
  /// level browsed belongs to the bucket it was listed in.
  package var connectionID: UUID? {
    didSet { if connectionID != oldValue { startOver() } }
  }
  /// The bucket's name, as typed — or a whole pasted location (`s3://bucket/folder/`), which
  /// « Browse » splits into the bucket and the prefix it names; changing it starts over.
  package var bucket = "" {
    didSet { if bucket != oldValue && !isAdopting { startOver() } }
  }
  /// Whether `bucket` is being rewritten to the name a pasted location held: not a new bucket.
  private var isAdopting = false
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
  private let provider: () -> [S3Connection]
  private var listing: Task<Void, Never>?

  /// A model over a fixed list of `connections`, listing through `browsing`.
  package convenience init(connections: [S3Connection], browsing: @escaping Browsing) {
    self.init(connectionsFrom: { connections }, browsing: browsing)
  }

  /// A model over the connections `provider` reads (Settings' store in the app), listing
  /// through `browsing`.
  package init(
    connectionsFrom provider: @escaping () -> [S3Connection], browsing: @escaping Browsing
  ) {
    self.provider = provider
    connections = provider()
    self.browsing = browsing
  }

  /// Reads the connections again (card 0177): one added in Settings while the sheet is up shows;
  /// the chosen one removed is no longer chosen, and edited (another endpoint, key or style) its
  /// level is read again — the folders shown were listed through what it was.
  package func reloadConnections() {
    let read = provider()
    guard read != connections else { return }
    let chosen = connections.first { $0.id == connectionID }
    connections = read
    guard let chosen else { return }
    if let now = read.first(where: { $0.id == chosen.id }) {
      if !Self.listsAlike(now, chosen) { startOver() }
    } else {
      connectionID = nil
    }
  }

  /// Reads the connections now, then again on every element of `changes` (each defaults write
  /// by default: the store keeps them there), until cancelled — the sheet's lifetime.
  package func followSettings<Changes: AsyncSequence>(_ changes: Changes) async {
    await DefaultsChanges.follow(changes) { reloadConnections() }
  }

  /// Whether `one` and `other` list a bucket the same way: a new name changes nothing read.
  private static func listsAlike(_ one: S3Connection, _ other: S3Connection) -> Bool {
    one.endpoint == other.endpoint && one.region == other.region
      && one.pathStyle == other.pathStyle && one.accessKey == other.accessKey
  }

  /// What the Import sheet would scan: `nil` until a connection and a bucket are both chosen.
  package var target: RemoteImportTarget? {
    let typed = Self.location(bucket)
    guard let connectionID, !typed.bucket.isEmpty else { return nil }
    return RemoteImportTarget(
      connectionID: connectionID, bucket: typed.bucket, prefix: typed.prefix ?? prefix)
  }

  /// What the bucket field holds: a bare name (`prefix` is `nil`: the browse decides where), or
  /// a location — `s3://bucket/folder`, `bucket/folder` — whose folder is the prefix meant.
  package static func location(_ text: String) -> (bucket: String, prefix: String?) {
    var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
    let scheme = "s3://"
    let hasScheme = rest.lowercased().hasPrefix(scheme)
    if hasScheme { rest = rest.dropFirst(scheme.count) }
    guard let slash = rest.firstIndex(of: "/") else {
      return (String(rest), hasScheme ? "" : nil)
    }
    let parts = rest[rest.index(after: slash)...].split(separator: "/")
    return (String(rest[..<slash]), parts.isEmpty ? "" : parts.joined(separator: "/") + "/")
  }

  /// One level of the way from the bucket's root to `prefix`.
  package struct Crumb: Equatable, Identifiable, Sendable {
    /// The folder's name; the bucket's for the root.
    package let name: String
    /// The full prefix of the level (`""` = the root).
    package let prefix: String
    package var id: String { prefix }
  }

  /// The levels from the bucket's root down to where the browse stands, the root first.
  package var crumbs: [Crumb] {
    var walked = ""
    let levels = prefix.split(separator: "/").map { part -> Crumb in
      walked += part + "/"
      return Crumb(name: String(part), prefix: walked)
    }
    return [Crumb(name: Self.location(bucket).bucket, prefix: "")] + levels
  }

  /// The prefix one level up, `nil` at the bucket's root.
  package var parent: String? {
    guard !prefix.isEmpty else { return nil }
    let parts = prefix.split(separator: "/").dropLast()
    return parts.isEmpty ? "" : parts.joined(separator: "/") + "/"
  }

  /// Lists the current prefix; a listing already running is replaced.
  package func browse() {
    adoptLocation()
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

  /// Lists the level the browse stands on unless it was read already, is being read, or failed:
  /// what the form does on its own when it opens, so the folders are there without a click.
  package func browseIfUnread() {
    guard !hasListed, !isBrowsing, error == nil else { return }
    browse()
  }

  /// A pasted location becomes the bucket it names and the prefix it points at.
  private func adoptLocation() {
    let typed = Self.location(bucket)
    guard let typedPrefix = typed.prefix else { return }
    startOver()
    isAdopting = true
    bucket = typed.bucket
    isAdopting = false
    prefix = typedPrefix
  }

  /// Goes to `folder` (a full prefix: one of `folders`, or a crumb's) and lists it.
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
