package import Foundation
package import ProjectKit
internal import RemoteKit
package import StackKit

// MARK: - Importing a bucket prefix (card 0169)

extension ImportPlanning {
  /// The client of a Settings connection; the app's one transport, as exports use it.
  package typealias Client = S3ClientLookup

  /// Lists one level of a bucket for « Browse »: the sub-prefixes alone, never the whole bucket.
  package nonisolated static func browsing(client: @escaping Client = ExportServices.liveClient)
    -> ImportBucketModel.Browsing
  {
    { connection, bucket, prefix in
      guard let s3 = try await client(connection) else {
        throw RemoteImportProblem.connectionMissing
      }
      return try await s3.list(bucket: bucket, prefix: prefix, delimiter: "/").prefixes
    }
  }

  /// Scans a bucket prefix where it stands and plans it against the library `index` holds.
  ///
  /// The frames stay in the bucket: only headers, side files and one centred run a frame are read
  /// (card 0167), and what was read is kept with the project so the next scan asks for less
  /// (card 0168). A connection that is gone, or whose secret is, is said — never an empty
  /// inventory, which would read as « this prefix holds no capture » (R2).
  package nonisolated static func remotePlanning(
    store: ProjectStore?, index: LibraryIndex, timeZone: TimeZone = .current,
    client: @escaping Client = ExportServices.liveClient
  ) -> ImportViewModel.RemotePlanning {
    { target, request, progress in
      guard let s3 = try await client(target.connectionID) else {
        throw RemoteImportProblem.connectionMissing
      }
      progress(.library)
      let masters = try await index.masters()
      try Task.checkCancellation()
      let scan = RemoteScan(
        store: .s3(s3, bucket: target.bucket), prefix: target.prefix, timeZone: timeZone)
      let scanned = try await scan.scan(
        cache: cachedScan(store, of: target), overrides: request.overrides, progress: progress)
      keep(scanned.cache, store, of: target)
      // What the scan listed proves a bucket master as the run will (card 0181).
      return ImportPlan(
        inventory: scanned.inventory, library: masters, request: request,
        identities: scanned.cache.identities(bucket: target.bucket))
    }
  }

  /// What the last scan of `target` read, `.empty` when there is none or this build cannot read
  /// it: a cache is spared reads, never correctness.
  package nonisolated static func cachedScan(_ store: ProjectStore?, of target: RemoteImportTarget)
    -> RemoteScanCache
  {
    guard let body = try? store?.remoteScan(of: target.path) ?? nil else { return .empty }
    return (try? RemoteScanCache(json: body)) ?? .empty
  }

  /// Keeps what this scan read for the next one; a project that refuses the write loses only the
  /// saved reads.
  nonisolated static func keep(
    _ cache: RemoteScanCache, _ store: ProjectStore?, of target: RemoteImportTarget
  ) {
    guard let store, let body = try? cache.json() else { return }
    try? store.setRemoteScan(body, of: target.path)
  }
}

extension ImportPlanning {
  /// The buckets a run of this project may read (card 0154): one store per remote source
  /// (card 0168), through the Settings connection its own row names, each looked up once.
  ///
  /// A source whose connection is gone contributes nothing: the run refuses with that bucket's
  /// name rather than stacking the lanes it could read (R2). A connection whose secret the
  /// Keychain refuses is kept with its refusal (card 0185): a run that reads that bucket is
  /// refused with those words before Siril starts, one that never does runs as before.
  package nonisolated static func runStores(
    _ sources: [ProjectSource], client: Client = ExportServices.liveClient
  ) async -> RunBuckets {
    var buckets = RunBuckets()
    var looked: [UUID: Result<S3Client?, any Error>] = [:]
    for source in sources where source.kind == .remoteNight {
      guard let bucket = source.bucket, !buckets.names(bucket),
        let id = source.connectionID.flatMap(UUID.init(uuidString:))
      else { continue }
      if looked[id] == nil {
        do { looked[id] = .success(try await client(id)) } catch { looked[id] = .failure(error) }
      }
      switch looked[id] {
      case .success(let s3?): buckets.stores.append(.s3(s3, bucket: bucket))
      case .failure(let error): buckets.refusals[bucket] = error
      case .success(nil), nil: continue
      }
    }
    buckets.stores.sort { $0.bucket < $1.bucket }
    return buckets
  }
}

/// Why a bucket could not be read for an import (card 0169).
package enum RemoteImportProblem: Error, Equatable, Sendable {
  /// The connection is gone from Settings, or its secret is.
  case connectionMissing
}
