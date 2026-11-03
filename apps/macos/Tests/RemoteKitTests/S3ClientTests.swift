import Foundation
import RemoteKit
import Testing

@Suite("S3Client lists, reads and fails like S3")
struct S3ClientTests {
  static func listing(_ keys: [(String, Int64, String)], truncated: Bool, next: String?)
    -> String
  {
    let contents = keys.map { key, size, etag in
      "<Contents><Key>\(key)</Key><LastModified>2026-10-18T21:04:05.123Z</LastModified>"
        + "<ETag>&quot;\(etag)&quot;</ETag><Size>\(size)</Size>"
        + "<StorageClass>STANDARD</StorageClass></Contents>"
    }.joined()
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      + "<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Name>astro</Name>"
      + "<Prefix>M31/</Prefix><KeyCount>\(keys.count)</KeyCount>"
      + "<IsTruncated>\(truncated)</IsTruncated>"
      + (next.map { "<NextContinuationToken>\($0)</NextContinuationToken>" } ?? "")
      + contents + "</ListBucketResult>"
  }

  @Test("A truncated listing is followed by its continuation token")
  func testListPaginates() async throws {
    let fake = Fake { _, call in
      call == 0
        ? .make(
          200,
          Self.listing(
            [("M31/a.fits", 1, "e1"), ("M31/b.fits", 2, "e2")], truncated: true, next: "tok/1+"))
        : .make(200, Self.listing([("M31/c.fits", 3, "e3")], truncated: false, next: nil))
    }

    let objects = try await fake.client().list(bucket: "astro", prefix: "M31/")

    #expect(objects.map(\.key) == ["M31/a.fits", "M31/b.fits", "M31/c.fits"])
    let requests = await fake.requests
    #expect(requests.count == 2)
    #expect(requests.map { $0.query("list-type") } == ["2", "2"])
    #expect(requests.map { $0.query("prefix") } == ["M31/", "M31/"])
    #expect(requests.map { $0.query("continuation-token") } == [nil, "tok/1+"])
    #expect(requests.map { $0.query("encoding-type") } == ["url", "url"])
  }

  @Test("Sizes beyond 4 GiB, unquoted ETags (multipart too) and dates are read")
  func testListParsesSizesAndETags() async throws {
    let fake = Fake { _, _ in
      .make(
        200,
        Self.listing(
          [
            ("M31/master.fit", 5_368_709_121, "9b2cf535f27731c974343645a3985328"),
            ("M31/big.fit", 70, "d41d8cd98f00b204e9800998ecf8427e-5"),
          ],
          truncated: false, next: nil))
    }

    let objects = try await fake.client().list(bucket: "astro", prefix: "M31/")

    #expect(objects.map(\.key) == ["M31/master.fit", "M31/big.fit"])
    #expect(objects.map(\.size) == [5_368_709_121, 70])
    #expect(
      objects.map(\.etag) == [
        "9b2cf535f27731c974343645a3985328", "d41d8cd98f00b204e9800998ecf8427e-5",
      ])
    #expect(objects.map(\.isSinglePartETag) == [true, false])
    // Fractional seconds survive the parse (to the millisecond, not bit for bit).
    for date in objects.map(\.lastModified) {
      let seconds = try #require(date?.timeIntervalSince1970)
      #expect(abs(seconds - 1_792_357_445.123) < 0.001)
    }
  }

  @Test("URL-encoded keys are decoded: + is a space, %2B a plus, %0D a carriage return")
  func testList_decodesURLEncodedKeys() async throws {
    let fake = Fake { _, _ in
      .make(
        200,
        "<ListBucketResult><EncodingType>url</EncodingType><IsTruncated>false</IsTruncated>"
          + "<Contents><Key>M31/nuit+1/a%2Bb%0D.fits</Key><Size>1</Size><ETag>e</ETag></Contents>"
          + "</ListBucketResult>")
    }

    let objects = try await fake.client().list(bucket: "astro", prefix: "M31/")

    #expect(objects.map(\.key) == ["M31/nuit 1/a+b\r.fits"])
  }

  @Test("A truncated page without a continuation token fails instead of stopping short")
  func testList_truncatedWithoutTokenFails() async throws {
    let fake = Fake { _, _ in
      .make(200, Self.listing([("M31/a.fits", 1, "e1")], truncated: true, next: nil))
    }

    await #expect(
      throws: S3Error.invalidResponse("truncated listing without NextContinuationToken")
    ) {
      try await fake.client().list(bucket: "astro", prefix: "M31/")
    }
  }

  @Test("A ranged GET answered 200 (Range ignored) is refused, never returned as the slice")
  func testGet_rangeIgnoredFails() async throws {
    let fake = Fake { _, _ in .make(200, "the whole object") }

    await #expect(throws: S3Error.invalidResponse("GET k: Range ignored (status 200)")) {
      try await fake.client().get(bucket: "astro", key: "k", range: 0...3)
    }
  }

  @Test("HEAD reads size, ETag and date; a 404 is nil")
  func testHead() async throws {
    let fake = Fake { request, _ in
      request.url.path.hasSuffix("missing.fits")
        ? .make(404)
        : .make(
          200,
          headers: [
            "content-length": "4096", "etag": "\"abc\"",
            "last-modified": "Sun, 18 Oct 2026 21:04:05 GMT",
          ])
    }
    let client = try fake.client()

    let found = try await client.head(bucket: "astro", key: "M31/a.fits")
    let missing = try await client.head(bucket: "astro", key: "M31/missing.fits")

    #expect(
      found
        == S3Object(
          key: "M31/a.fits", size: 4096, etag: "abc",
          lastModified: Date(timeIntervalSince1970: 1_792_357_445)))
    #expect(missing == nil)
    #expect(await fake.requests.map(\.method) == ["HEAD", "HEAD"])
  }

  @Test("A ranged GET sends an inclusive byte range, signed")
  func testGetSendsRange() async throws {
    let fake = Fake { _, _ in .make(206, "0123456789") }

    let data = try await fake.client().get(bucket: "astro", key: "M31/a.fits", range: 100...109)

    #expect(data == Data("0123456789".utf8))
    let request = try #require(await fake.requests.first)
    #expect(request.method == "GET")
    #expect(request.headers["range"] == "bytes=100-109")
    #expect(request.headers["authorization"]?.contains("range;") == true)
  }

  @Test("An S3 error keeps its status, code and message as sent")
  func testErrorCarriesS3Code() async throws {
    let message = "The request signature we calculated does not match the signature you provided."
    let fake = Fake { _, _ in .error(403, code: "SignatureDoesNotMatch", message: message) }

    let error = await #expect(throws: S3Error.self) {
      try await fake.client().list(bucket: "astro", prefix: "")
    }

    #expect(
      error
        == .service(status: 403, code: "SignatureDoesNotMatch", message: message, requestID: "R1"))
    #expect(error?.description == "S3 403 SignatureDoesNotMatch: \(message)")
    #expect(await fake.requests.count == 1)
  }

  struct RetryRow: Sendable, CustomTestStringConvertible {
    let label: String
    let failure: @Sendable () throws -> HTTPResponse
    let calls: Int
    let succeeds: Bool
    var testDescription: String { label }
  }

  static let retryRows: [RetryRow] = [
    RetryRow(
      label: "503 twice then 200", failure: { .error(503, code: "SlowDown", message: "s") },
      calls: 3, succeeds: true),
    RetryRow(
      label: "timeout twice then 200", failure: { throw URLError(.timedOut) }, calls: 3,
      succeeds: true),
    RetryRow(
      label: "429 throttling retried",
      failure: { .error(429, code: "SlowDown", message: "s") }, calls: 3, succeeds: true),
    RetryRow(
      label: "400 RequestTimeout retried",
      failure: { .error(400, code: "RequestTimeout", message: "t") }, calls: 3, succeeds: true),
    RetryRow(
      label: "501 NotImplemented never retried",
      failure: { .error(501, code: "NotImplemented", message: "no") }, calls: 1, succeeds: false),
    RetryRow(
      label: "403 never retried", failure: { .error(403, code: "AccessDenied", message: "no") },
      calls: 1, succeeds: false),
    RetryRow(
      label: "404 never retried", failure: { .error(404, code: "NoSuchKey", message: "no") },
      calls: 1, succeeds: false),
    RetryRow(
      label: "offline never retried", failure: { throw URLError(.notConnectedToInternet) },
      calls: 1, succeeds: false),
  ]

  @Test("Only 5xx and timeouts are retried, three tries, each one reported", arguments: retryRows)
  func testRetriesOnly5xx(row: RetryRow) async throws {
    let fake = Fake { _, call in
      call < 2 ? try row.failure() : .make(206, "ok")
    }
    let sleeps = SleepLog()
    let events = EventLog()

    let result = try? await fake.client(sleeps: sleeps).get(
      bucket: "astro", key: "k", range: 0...1, progress: { event in events.append(event) })

    #expect((result != nil) == row.succeeds)
    #expect(await fake.requests.count == row.calls)
    #expect(await sleeps.delays.count == row.calls - 1)
    #expect(events.retries == Array(1..<row.calls))
  }

  @Test("After three failed tries the last error is thrown")
  func testRetries_giveUpAfterThree() async throws {
    let fake = Fake { _, _ in .error(500, code: "InternalError", message: "boom") }
    let sleeps = SleepLog()

    await #expect(
      throws: S3Error.service(status: 500, code: "InternalError", message: "boom", requestID: "R1")
    ) {
      try await fake.client(sleeps: sleeps).get(bucket: "astro", key: "k", range: nil)
    }
    #expect(await fake.requests.count == 3)
    #expect(await sleeps.delays == [.milliseconds(500), .milliseconds(1000)])
  }

  /// A `delimiter=/` answer: the keys of this level, and the sub-prefixes below it.
  static func level(
    _ keys: [(String, Int64, String)], folders: [String], truncated: Bool, next: String?
  ) -> String {
    let common = folders.map { "<CommonPrefixes><Prefix>\($0)</Prefix></CommonPrefixes>" }.joined()
    // A real answer to `encoding-type=url` echoes it: that is what says the names are encoded.
    return Self.listing(keys, truncated: truncated, next: next)
      .replacingOccurrences(
        of: "</ListBucketResult>",
        with: common + "<Delimiter>/</Delimiter><EncodingType>url</EncodingType>"
          + "</ListBucketResult>")
  }

  @Test("testListWithDelimiter_CommonPrefixes: one level answers its folders and its own keys")
  func testListWithDelimiter_CommonPrefixes() async throws {
    let fake = Fake { _, call in
      call == 0
        ? .make(
          200,
          Self.level(
            [("M31/info.txt", 12, "e1")], folders: ["M31/2026-10-18/", "M31/2026-10-19/"],
            truncated: true, next: "tok"))
        : .make(
          200,
          Self.level(
            [("M31/notes.txt", 3, "e2")], folders: ["M31/flats%2Fdarks/"], truncated: false,
            next: nil))
    }

    let level = try await fake.client().list(bucket: "astro", prefix: "M31/", delimiter: "/")

    #expect(level.objects.map(\.key) == ["M31/info.txt", "M31/notes.txt"])
    #expect(
      level.prefixes == ["M31/2026-10-18/", "M31/2026-10-19/", "M31/flats/darks/"],
      "every page's folders, URL-decoded like the keys")
    let requests = await fake.requests
    #expect(requests.map { $0.query("delimiter") } == ["/", "/"], "signed on both pages")
    #expect(requests.map { $0.query("prefix") } == ["M31/", "M31/"])
    #expect(requests.map { $0.query("encoding-type") } == ["url", "url"])
  }

  @Test("a listing without a delimiter asks for none and still answers every key")
  func testListWithoutDelimiter() async throws {
    let fake = Fake { _, _ in
      .make(200, Self.listing([("M31/a.fits", 1, "e1")], truncated: false, next: nil))
    }

    let objects = try await fake.client().list(bucket: "astro", prefix: "M31/")

    #expect(objects.map(\.key) == ["M31/a.fits"])
    #expect(await fake.requests.map { $0.query("delimiter") } == [nil])
  }
}
