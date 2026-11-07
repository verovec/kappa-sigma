import Foundation
import RemoteKit
import TestSupport
import Testing

/// The live S3 suites' one configuration (card 0183): read from the environment `just s3-live`
/// sets, so these run on every host — the live suites themselves skip on CI.
@Suite("Live S3 environment: one configuration for the three live suites")
struct LiveS3EnvironmentTests {
  /// What a configuration reads.
  struct Expected: Sendable {
    let url: String
    let region: String
    let bucket: String
    let access: String
    let path: Bool
  }

  struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    let env: [String: String]
    /// `nil`: the suites skip.
    let expected: Expected?
    var testDescription: String { name }
  }

  static let rows: [Row] = [
    Row(name: "unset: skip", env: [:], expected: nil),
    Row(
      name: "skip flag wins over an endpoint",
      env: ["ASTROSTACK_SKIP_LIVE": "1", "ASTROSTACK_S3_LIVE_ENDPOINT": "http://127.0.0.1:9000"],
      expected: nil),
    Row(
      name: "not an http(s) URL: skip", env: ["ASTROSTACK_S3_LIVE_ENDPOINT": "ftp://host"],
      expected: nil),
    Row(
      name: "MinIO defaults", env: ["ASTROSTACK_S3_LIVE_ENDPOINT": "http://127.0.0.1:9000"],
      expected: Expected(
        url: "http://127.0.0.1:9000", region: "us-east-1", bucket: "astrostack-live",
        access: "minioadmin", path: true)),
    Row(
      name: "a real bucket from .env, virtual-host",
      env: [
        "ASTROSTACK_S3_LIVE_ENDPOINT": "https://s3.example.net",
        "ASTROSTACK_S3_LIVE_REGION": "eu-west-3", "ASTROSTACK_S3_LIVE_BUCKET": "po-test",
        "ASTROSTACK_S3_LIVE_ACCESS_KEY": "AKIA0", "ASTROSTACK_S3_LIVE_SECRET_KEY": "s",
        "ASTROSTACK_S3_LIVE_ADDRESSING": "virtual",
      ],
      expected: Expected(
        url: "https://s3.example.net", region: "eu-west-3", bucket: "po-test", access: "AKIA0",
        path: false)),
  ]

  @Test("testConfigurationFromEnvironment", arguments: rows)
  func testConfigurationFromEnvironment(_ row: Row) throws {
    let live = LiveS3Environment(environment: row.env)
    guard let expected = row.expected else {
      #expect(live == nil)
      return
    }
    let found = try #require(live)
    #expect("\(found.endpoint.scheme)://\(found.endpoint.host)" == expected.url)
    #expect(found.endpoint.region == expected.region)
    #expect(found.bucket == expected.bucket)
    #expect(found.credentials.accessKey == expected.access)
    #expect((found.endpoint.addressing == .pathStyle) == expected.path)
  }

  @Test(
    "testOnlyJustS3LiveRunsTheSuites",
    arguments: [
      ([:], false),
      (["ASTROSTACK_S3_LIVE_ENDPOINT": "https://s3.example.net"], false),  // .env alone: no
      (["ASTROSTACK_S3_LIVE": "1"], true),
      (["ASTROSTACK_S3_LIVE": "1", "ASTROSTACK_SKIP_LIVE": "1"], false),
    ] as [([String: String], Bool)])
  func testOnlyJustS3LiveRunsTheSuites(_ env: [String: String], _ requested: Bool) {
    #expect(LiveS3Environment.isRequested(env) == requested)
  }

  @Test("testRunPrefixIsDatedAndUnique")
  func testRunPrefixIsDatedAndUnique() {
    let now = Date(timeIntervalSince1970: 1_794_052_800)  // 2026-11-07 12:00 UTC
    let first = LiveS3Environment.runPrefix(now: now)
    let second = LiveS3Environment.runPrefix(now: now)
    #expect(first.hasPrefix("astrostack-live/20261107-"))
    #expect(first.hasSuffix("/"))
    #expect(first != second)
  }

  @Test("testPrefixSweepKeepsToday")
  func testPrefixSweepKeepsToday() {
    let now = Date(timeIntervalSince1970: 1_794_052_800)  // 2026-11-07 12:00 UTC
    let keys = [
      "astrostack-live/20261107-a/x.fit",  // today: a run may be writing it
      "astrostack-live/20261106-b/x.fit",  // yesterday: within the day's grace
      "astrostack-live/20261104-c/x.fit",  // stale: a killed run left it
      "astrostack-live/20261104-c/sub/y.fit",
      "astrostack-live/not-a-date/x.fit",  // never ours to judge
      "captures/20200101-d/x.fit",  // outside the live root: never touched
    ]
    #expect(
      LiveS3Environment.staleKeys(keys, now: now)
        == ["astrostack-live/20261104-c/x.fit", "astrostack-live/20261104-c/sub/y.fit"])
  }
}
