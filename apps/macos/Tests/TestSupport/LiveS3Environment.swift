package import Foundation
package import RemoteKit
internal import Synchronization
package import Testing

/// The live S3 suites' one configuration (card 0183): `LiveS3Tests`, `LiveExportS3Tests` and
/// `RemotePipelineLiveTests` read it from the environment `just s3-live` sets.
///
/// They run only under `just s3-live` (`ASTROSTACK_S3_LIVE=1`, `isRequested`): an endpoint left in
/// `.env` never turns them on inside `just check`. A local MinIO by default (minioadmin keys,
/// path-style, bucket `astrostack-live`); a real bucket when `.env` names one. Every test writes
/// under its own `runPrefix()` and removes it; what a killed run left is reaped a day later by the
/// next process (`sweepOnce`).
package struct LiveS3Environment: Sendable {
  /// What the helpers refuse.
  package enum Refusal: Error, Equatable {
    /// Only a run's own prefix is ever deleted.
    case notARunPrefix(String)
  }

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

  /// True when `environment` asks for the live S3 suites: `just s3-live` sets
  /// `ASTROSTACK_S3_LIVE=1`; `ASTROSTACK_SKIP_LIVE=1` still wins.
  package static func isRequested(_ environment: [String: String]) -> Bool {
    environment["ASTROSTACK_S3_LIVE"] == "1" && environment["ASTROSTACK_SKIP_LIVE"] != "1"
  }

  /// The configuration `environment` names; `nil` (a requested suite then fails) without
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

  /// A client of the endpoint, over the one transport of this process (a URLSession is never
  /// invalidated: one per process, not one per test).
  package func client() -> S3Client {
    S3Client(endpoint: endpoint, credentials: credentials, transport: Self.transport)
  }

  private static let transport = HTTPTransport.urlSession()

  /// One test's run: the bucket made sure of, what killed runs left swept (once per process, best
  /// effort), and a prefix of its own handed to `body` with the client; the prefix is removed
  /// afterwards whether `body` returned, threw or was cancelled.
  package func withRun(_ body: (S3Client, String) async throws -> Void) async throws {
    let client = client()
    try await ensureBucket(client)
    await sweepOnce(client: client)
    let prefix = Self.runPrefix()
    do {
      try await body(client, prefix)
    } catch {
      await removeUncancelled(prefix, client)
      throw error
    }
    await removeUncancelled(prefix, client)
  }

  /// `removePrefix` in a task of its own: a test cancelled by its time limit still cleans up.
  private func removeUncancelled(_ prefix: String, _ client: S3Client) async {
    let removal = await Task { try await removePrefix(prefix, client: client) }.result
    if case .failure(let error) = removal {
      Issue.record("could not remove \(prefix) from \(bucket): \(error)")
    }
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
  /// these keys) is used as is, so a real bucket needs no CreateBucket permission. Outside
  /// `us-east-1` the creation names its region, as S3 requires.
  package func ensureBucket(_ client: S3Client) async throws {
    do {
      _ = try await client.list(bucket: bucket, prefix: Self.root, limit: 1)
      return
    } catch S3Error.service(404, _, _, _) {}
    let body =
      endpoint.region == "us-east-1"
      ? nil
      : Data(
        ("<CreateBucketConfiguration xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
          + "<LocationConstraint>\(endpoint.region)</LocationConstraint>"
          + "</CreateBucketConfiguration>").utf8)
    let request = try S3Request(method: "PUT", bucket: bucket, key: "", body: body)
      .prepared(
        endpoint: endpoint, signer: SigV4(credentials: credentials, region: endpoint.region),
        date: Date())
    let response = try await Self.transport.send(request)
    guard response.isSuccess || response.status == 409 else {
      // The service's own answer, as sent: its <Code> and <Message> say why.
      throw S3Error.service(
        status: response.status, code: "CreateBucket \(bucket)",
        message: String(bytes: response.body.prefix(600), encoding: .utf8), requestID: nil)
    }
  }

  /// Deletes every object under `prefix` (a run's own cleanup); a prefix that is not a run's
  /// (outside `root`, or `root` itself) is refused, never listed.
  package func removePrefix(_ prefix: String, client: S3Client) async throws {
    guard prefix.hasPrefix(Self.root), prefix.count > Self.root.count else {
      throw Refusal.notARunPrefix(prefix)
    }
    try await delete(try await client.list(bucket: bucket, prefix: prefix).map(\.key), client)
  }

  /// Deletes what runs killed more than a day ago left under `root`; never anything else.
  package func sweep(client: S3Client, now: Date = Date()) async throws {
    let keys = try await client.list(bucket: bucket, prefix: Self.root).map(\.key)
    try await delete(Self.staleKeys(keys, now: now), client)
  }

  /// `sweep`, the first time a test of this process asks; later calls do nothing. Housekeeping:
  /// a sweep that fails fails no test (the next process tries again).
  package func sweepOnce(client: S3Client) async {
    let first = Self.swept.withLock { swept in
      defer { swept = true }
      return !swept
    }
    if first { try? await sweep(client: client) }
  }

  private static let swept = Mutex(false)

  /// Deletes `keys`, `limit` requests in flight.
  private func delete(_ keys: [String], _ client: S3Client) async throws {
    try await Self.forEach(keys) { [bucket] key in
      try await client.delete(bucket: bucket, key: key)
    }
  }

  /// Runs `body` over `items`, `limit` at a time.
  package static func forEach(
    _ items: [String], limit: Int = 8, _ body: @escaping @Sendable (String) async throws -> Void
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (index, item) in items.enumerated() {
        if index >= limit { try await group.next() }
        group.addTask { try await body(item) }
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
  /// Runs a live S3 suite under `just s3-live` alone; skips it, saying so, everywhere else.
  package static var liveS3: Self {
    .enabled(
      if: LiveS3Environment.isRequested(ProcessInfo.processInfo.environment),
      "run by `just s3-live` only (ASTROSTACK_S3_LIVE unset)")
  }
}
