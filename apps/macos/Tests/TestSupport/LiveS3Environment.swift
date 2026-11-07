package import Foundation
package import RemoteKit
package import Testing

/// The live S3 suites' one configuration (card 0183): `LiveS3Tests`, `LiveExportS3Tests` and
/// `RemotePipelineLiveTests` read it from the environment `just s3-live` sets.
///
/// A local MinIO by default (minioadmin keys, path-style, bucket `astrostack-live`); a real bucket
/// when `.env` names one. Every run writes under its own `runPrefix()` and removes it; a run killed
/// before its cleanup is reaped by the next one (`sweep`), a day later.
package struct LiveS3Environment: Sendable {
  /// Where the service answers.
  package let endpoint: S3Endpoint
  /// The keys (minioadmin unless given).
  package let credentials: S3Credentials
  /// The bucket the suites write under a prefix of.
  package let bucket: String

  /// The folder of the bucket every live run writes under, and the only one `sweep` touches.
  package static let root = "astrostack-live/"
  /// A prefix older than this belongs to no running suite.
  package static let staleAge: TimeInterval = 24 * 3600

  /// The configuration `environment` names; `nil` (the suites skip) without
  /// `ASTROSTACK_S3_LIVE_ENDPOINT`, with a non-http(s) one, or under `ASTROSTACK_SKIP_LIVE=1`.
  package init?(environment: [String: String]) {
    guard environment["ASTROSTACK_SKIP_LIVE"] != "1",
      let text = environment["ASTROSTACK_S3_LIVE_ENDPOINT"], let url = URL(string: text),
      let endpoint = try? S3Endpoint(
        url: url, region: environment["ASTROSTACK_S3_LIVE_REGION"] ?? "us-east-1",
        addressing: environment["ASTROSTACK_S3_LIVE_ADDRESSING"] == "virtual"
          ? .virtualHost : .pathStyle)
    else { return nil }
    self.endpoint = endpoint
    credentials = S3Credentials(
      accessKey: environment["ASTROSTACK_S3_LIVE_ACCESS_KEY"] ?? "minioadmin",
      secretKey: environment["ASTROSTACK_S3_LIVE_SECRET_KEY"] ?? "minioadmin")
    bucket = environment["ASTROSTACK_S3_LIVE_BUCKET"] ?? "astrostack-live"
  }

  /// This process's configuration.
  package static var current: Self? { Self(environment: ProcessInfo.processInfo.environment) }

  /// A client of the endpoint over `transport`.
  package func client(transport: HTTPTransport = .urlSession()) -> S3Client {
    S3Client(endpoint: endpoint, credentials: credentials, transport: transport)
  }

  /// A prefix of one run alone: `astrostack-live/<yyyyMMdd>-<uuid>/`, its day first so `sweep`
  /// can tell a killed run's leftovers from a running one's.
  package static func runPrefix(now: Date = Date()) -> String {
    "\(root)\(day(of: now))-\(UUID().uuidString)/"
  }

  /// The keys of `keys` a run older than `staleAge` left under `root`; a key whose run segment
  /// carries no day is never judged (it is not ours to delete).
  package static func staleKeys(_ keys: [String], now: Date) -> [String] {
    let cutoff = day(of: now.addingTimeInterval(-staleAge))
    return keys.filter { key in
      guard key.hasPrefix(root) else { return false }
      let run = key.dropFirst(root.count).prefix { $0 != "/" }
      let stamp = run.prefix(8)
      guard stamp.count == 8, stamp.allSatisfy(\.isASCII), stamp.allSatisfy(\.isNumber),
        run.dropFirst(8).first == "-"
      else { return false }
      return stamp < cutoff
    }
  }

  /// The bucket, created when the service says it does not exist; an existing one (listable with
  /// these keys) is used as is, so a real bucket needs no CreateBucket permission.
  package func ensureBucket(_ client: S3Client, transport: HTTPTransport = .urlSession())
    async throws
  {
    do {
      _ = try await client.list(bucket: bucket, prefix: Self.root, limit: 1)
      return
    } catch S3Error.service(404, _, _, _) {}
    let request = try S3Request(method: "PUT", bucket: bucket, key: "")
      .prepared(
        endpoint: endpoint, signer: SigV4(credentials: credentials, region: endpoint.region),
        date: Date())
    let response = try await transport.send(request)
    guard response.isSuccess || response.status == 409 else {
      throw S3Error.service(
        status: response.status, code: "CreateBucket", message: bucket, requestID: nil)
    }
  }

  /// Deletes every object under `prefix` (a run's own cleanup).
  package func removePrefix(_ prefix: String, client: S3Client) async throws {
    precondition(prefix.hasPrefix(Self.root) && prefix.count > Self.root.count)
    try await delete(try await client.list(bucket: bucket, prefix: prefix).map(\.key), client)
  }

  /// Deletes what runs killed more than a day ago left under `root`; never anything else.
  package func sweep(client: S3Client, now: Date = Date()) async throws {
    let keys = try await client.list(bucket: bucket, prefix: Self.root).map(\.key)
    try await delete(Self.staleKeys(keys, now: now), client)
  }

  /// Deletes `keys`, eight requests in flight.
  private func delete(_ keys: [String], _ client: S3Client) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (index, key) in keys.enumerated() {
        if index >= 8 { try await group.next() }
        group.addTask { [bucket] in try await client.delete(bucket: bucket, key: key) }
      }
      try await group.waitForAll()
    }
  }

  /// `yyyyMMdd` of `date`, UTC: one spelling on every host.
  private static func day(of date: Date) -> String {
    date.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
  }
}

extension Trait where Self == ConditionTrait {
  /// Skips a live S3 suite, saying why, when no endpoint is configured (`just s3-live` sets it).
  package static var liveS3: Self {
    .enabled(
      if: LiveS3Environment.current != nil, "ASTROSTACK_S3_LIVE_ENDPOINT unset (just s3-live)")
  }
}
