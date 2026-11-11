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
      return try await s3.listPrefixes(bucket: bucket, prefix: prefix, delimiter: "/")
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
    let planner = CapturePlanner(store: store, index: index, timeZone: timeZone, client: client)
    return { target, request, progress in
      // The sheet's prefix is not a source yet: its connection is the one the user just chose.
      try await planner.plan(request, targets: [target.path: target], progress: progress)
    }
  }

  /// Plans `request` against the library `index` holds, wherever its paths are read from
  /// (card 0190): folders of this Mac, and bucket prefixes through the connection the project's
  /// source of that path records.
  ///
  /// A request of folders alone is today's local plan, untouched. A bucket path with no source,
  /// or whose connection is gone, fails the plan — never the folders alone (R2).
  @concurrent
  package nonisolated static func plan(
    _ request: ImportRequest, store: ProjectStore?, index: LibraryIndex, timeZone: TimeZone,
    client: @escaping Client = ExportServices.liveClient,
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> ImportPlan {
    let remote = request.paths.filter { ProjectSource.remoteFolder(of: $0) != nil }
    guard !remote.isEmpty else {
      return try await plan(request, index: index, timeZone: timeZone, progress: progress)
    }
    let sources = try store?.sources() ?? []
    var targets: [String: RemoteImportTarget] = [:]
    for path in remote {
      targets[path] = sources.first { $0.kind == .remoteNight && $0.path == path }
        .flatMap(RemoteImportTarget.init(source:))
    }
    return try await CapturePlanner(
      store: store, index: index, timeZone: timeZone, client: client
    ).plan(request, targets: targets, progress: progress)
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
      // A bucket already read is done; one refused so far may still be read by another
      // connection, which then wins (a refused connection never hides a working one).
      guard let bucket = source.bucket, !buckets.stores.contains(where: { $0.bucket == bucket }),
        let id = source.connectionID.flatMap(UUID.init(uuidString:))
      else { continue }
      if looked[id] == nil {
        do { looked[id] = .success(try await client(id)) } catch { looked[id] = .failure(error) }
      }
      switch looked[id] {
      case .success(let s3?):
        // A name this connection cannot address (0184) is refused before Siril, in its words.
        do { try s3.endpoint.validate(bucket: bucket) } catch {
          buckets.refusals[bucket] = buckets.refusals[bucket] ?? error
          continue
        }
        buckets.stores.append(.s3(s3, bucket: bucket))
        buckets.refusals[bucket] = nil
      case .failure(let error): buckets.refusals[bucket] = buckets.refusals[bucket] ?? error
      case .success(nil), nil: continue
      }
    }
    buckets.stores.sort { $0.bucket < $1.bucket }
    return buckets
  }
}

extension ImportPlanning {
  /// The stager of a master rebuilt from a bucket (Données): it checks each download against a
  /// listing made now (card 0186), as a run's does against the run's — a frame uploaded again
  /// mid-rebuild fails it, named, instead of signing a master with bytes nothing listed.
  package nonisolated static func rebuildStager(stores: [RemoteObjectStore], paths: [String])
    async throws -> FrameStager
  {
    FrameStager(
      stores: stores, expected: try await FrameStager(stores: stores).identities(of: paths))
  }
}

/// Why a bucket could not be read for an import (card 0169).
package enum RemoteImportProblem: Error, Equatable, Sendable {
  /// The connection is gone from Settings, or its secret is.
  case connectionMissing
  /// Two nights of the project name the same bucket through two connections, one prefix inside
  /// the other (card 0190): a frame's path names its bucket, not its connection, so the capture
  /// cannot be told apart.
  case bucketOnTwoConnections(String)
}
