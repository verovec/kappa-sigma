package import Foundation
package import RemoteKit
package import Testing

/// The live S3 suites' one configuration (card 0183): `LiveS3Tests`, `LiveExportS3Tests`,
/// `RemotePipelineLiveTests` and `LiveRemoteStagerTests` read it from the environment
/// `just s3-live` sets.
///
/// They run only under `just s3-live` (`ASTROSTACK_S3_LIVE=1`, `isRequested`): an endpoint left in
/// `.env` never turns them on inside `just check`. A local MinIO by default (minioadmin keys,
/// path-style, bucket `astrostack-live`); a real bucket when `.env` names one. Every test writes
/// under its own `runPrefix()` and removes it; what a killed run left is reaped a day later
/// (`sweep`, run by `LiveS3Tests.testSweepRemovesDayOldRunsOnly`).
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
  package init?(environment given: [String: String]) {
    // A placeholder line of `.env` (`KEY=`) is no value: the default applies.
    let environment = given.filter { !$0.value.isEmpty }
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

  /// One test's run: the bucket made sure of, and a prefix of its own handed to `body` with the
  /// client; the prefix is removed afterwards whether `body` returned, threw or was cancelled,
  /// and listed again to prove it (a DELETE answers 204 even for a key it did not find).
  package func withRun(_ body: (S3Client, String) async throws -> Void) async throws {
    let client = client()
    try await ensureBucket(client)
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
    let removal = await Task {
      try await removePrefix(prefix, client: client)
      return try await client.list(bucket: bucket, prefix: prefix).map(\.key)
    }.result
    switch removal {
    case .success(let left) where !left.isEmpty:
      Issue.record("\(left.count) objects left under \(prefix) after removal: \(left.prefix(3))")
    case .failure(let error):
      Issue.record("could not remove \(prefix) from \(bucket): \(error)")
    case .success: break
    }
  }

  /// A prefix of one run alone: `astrostack-live/<yyyyMMdd>-<uuid>/`, its day first so `sweep`
  /// can tell a killed run's leftovers from a running one's.
  package static func runPrefix(now: Date = Date()) -> String {
    "\(root)\(day(of: now))-\(UUID().uuidString)/"
  }

  /// The keys of `keys` a run older than `staleAge` left under `root`; a key whose run segment is
  /// not `<yyyyMMdd>-<UUID>` (a real day, a whole UUID) is never judged: it is not ours to delete.
  package static func staleKeys(_ keys: [String], now: Date) -> [String] {
    let cutoff = day(of: now.addingTimeInterval(-staleAge))
    return keys.filter { key in
      guard key.hasPrefix(root) else { return false }
      let run = key.dropFirst(root.count).prefix { $0 != "/" }
      guard let stamp = runDay(String(run)) else { return false }
      return stamp < cutoff
    }
  }

  /// True for a run's own prefix and nothing wider: `root` + `<yyyyMMdd>-<UUID>` + `/`.
  package static func isRunPrefix(_ prefix: String) -> Bool {
    guard prefix.hasPrefix(root), prefix.hasSuffix("/") else { return false }
    let run = prefix.dropFirst(root.count).dropLast()
    return !run.contains("/") && runDay(String(run)) != nil
  }

  /// The day of a run segment `<yyyyMMdd>-<UUID>`, `nil` for anything else.
  private static func runDay(_ run: String) -> String? {
    let stamp = String(run.prefix(8))
    guard run.dropFirst(8).first == "-", UUID(uuidString: String(run.dropFirst(9))) != nil,
      stamp.allSatisfy(\.isASCII), stamp.allSatisfy(\.isNumber),
      let parsed = try? Date(stamp, strategy: dayStyle), day(of: parsed) == stamp
    else { return nil }
    return stamp
  }

  private static let dayStyle = Date.ISO8601FormatStyle().year().month().day()
    .dateSeparator(.omitted)

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

  /// Deletes every object under `prefix` (a run's own cleanup); anything but a run's own prefix
  /// (`isRunPrefix`) is refused, never listed: another session's runs share the bucket.
  package func removePrefix(_ prefix: String, client: S3Client) async throws {
    guard Self.isRunPrefix(prefix) else { throw Refusal.notARunPrefix(prefix) }
    try await delete(try await client.list(bucket: bucket, prefix: prefix).map(\.key), client)
  }

  /// Deletes what runs killed more than a day ago left under `root`; never anything else.
  package func sweep(client: S3Client, now: Date = Date()) async throws {
    let keys = try await client.list(bucket: bucket, prefix: Self.root).map(\.key)
    try await delete(Self.staleKeys(keys, now: now), client)
  }

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
  private static func day(of date: Date) -> String { date.formatted(dayStyle) }
}

extension Trait where Self == ConditionTrait {
  /// Runs a live S3 suite under `just s3-live` alone; skips it, saying so, everywhere else.
  package static var liveS3: Self {
    .enabled(
      if: LiveS3Environment.isRequested(ProcessInfo.processInfo.environment),
      "run by `just s3-live` only (ASTROSTACK_S3_LIVE unset)")
  }
}
