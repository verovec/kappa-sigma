internal import Foundation
internal import ProjectKit
internal import RemoteKit
internal import StackKit

/// Plans a capture read from folders of this Mac and bucket prefixes at once (card 0190): one
/// `CaptureScan` over every path of the request, then the plan against the library.
///
/// What each prefix answered is kept with the project (card 0168), and proves a bucket master
/// as the run will (card 0181).
nonisolated struct CapturePlanner: Sendable {
  /// The project the scan's reads are kept with; `nil` keeps nothing.
  var store: ProjectStore?
  /// The calibration library the plan is matched against.
  var index: LibraryIndex
  /// The site's zone: it decides each frame's observing night.
  var timeZone: TimeZone
  /// The client of a Settings connection.
  var client: ImportPlanning.Client

  /// The plan of `request`, each bucket path of it read through its target of `targets`.
  ///
  /// A bucket path without a target, or whose connection is gone, throws
  /// `RemoteImportProblem.connectionMissing`: never a plan of the other paths alone (R2).
  @concurrent
  func plan(
    _ request: ImportRequest, targets: [String: RemoteImportTarget],
    progress: @escaping @Sendable (ScanProgress) -> Void
  ) async throws -> ImportPlan {
    var roots: [CaptureScan.Root] = []
    var read: [RemoteImportTarget] = []
    // One lookup a connection, as a run's stores do: the Keychain may wait on the user.
    var clients: [UUID: S3Client] = [:]
    // A prefix another one of the request covers is never read: its connection has no say.
    let covered = CaptureScan.covered(
      request.paths.map { ProjectSource.remoteFolder(of: $0) == nil ? nil : $0 })
    for (index, path) in request.paths.enumerated() where !covered.contains(index) {
      guard ProjectSource.remoteFolder(of: path) != nil else {
        roots.append(.folder(path))
        continue
      }
      // A Keychain lookup may wait on the user: a cancelled plan asks for no more of them.
      try Task.checkCancellation()
      guard let target = targets[path] else { throw RemoteImportProblem.connectionMissing }
      if clients[target.connectionID] == nil {
        clients[target.connectionID] = try await client(target.connectionID)
      }
      guard let s3 = clients[target.connectionID] else {
        throw RemoteImportProblem.connectionMissing
      }
      let cache = ImportPlanning.cachedScan(store, of: target)
      roots.append(
        .prefix(.init(store: .s3(s3, bucket: target.bucket), prefix: target.prefix, cache: cache)))
      read.append(target)
    }
    progress(.library)
    let masters = try await index.masters()
    try Task.checkCancellation()
    let scanned = try await CaptureScan(roots: roots, timeZone: timeZone)
      .scan(overrides: request.overrides, progress: progress)
    var identities: [String: String] = [:]
    for target in read {
      guard let cache = scanned.caches[target.path] else { continue }
      ImportPlanning.keep(cache, store, of: target)
      identities.merge(cache.identities(bucket: target.bucket)) { $1 }
    }
    return ImportPlan(
      inventory: scanned.inventory, library: masters, request: request, identities: identities)
  }
}
