package import Foundation
internal import os

/// The five S3 calls AstroStack needs (list, head, ranged get, download, upload) against any
/// S3-compatible endpoint, signed with SigV4.
///
/// A value over an injected transport: it holds no mutable state, so concurrent calls need no
/// actor. Each request is re-signed per try; only 5xx answers and timeouts are retried.
package struct S3Client: Sendable {
  /// Retry and transfer sizes.
  package struct Policy: Sendable, Equatable {
    /// Tries per request, the first included.
    package var tries: Int
    /// The first backoff; each later one doubles.
    package var backoff: Duration
    /// Files of at least this size upload in parts.
    package var multipartThreshold: Int64
    /// The size of each part but the last.
    package var partSize: Int

    /// Three tries from 500 ms, multipart from 64 MiB in 16 MiB parts.
    package init(
      tries: Int = 3, backoff: Duration = .milliseconds(500),
      multipartThreshold: Int64 = 64 << 20, partSize: Int = 16 << 20
    ) {
      self.tries = tries
      self.backoff = backoff
      self.multipartThreshold = multipartThreshold
      self.partSize = partSize
    }
  }

  /// Waits between tries (`Task.sleep` live, recorded in tests).
  package typealias Sleep = @Sendable (Duration) async throws -> Void

  static let logger = Logger(subsystem: "fr.astrostack", category: "RemoteKit/s3")

  /// Where requests go.
  package let endpoint: S3Endpoint
  let signer: SigV4
  let transport: HTTPTransport
  let policy: Policy
  let clock: @Sendable () -> Date
  let sleep: Sleep

  /// Creates a client; `clock` and `sleep` are injected so tests neither wait nor depend on time.
  package init(
    endpoint: S3Endpoint, credentials: S3Credentials, transport: HTTPTransport,
    policy: Policy = Policy(), clock: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.endpoint = endpoint
    self.signer = SigV4(credentials: credentials, region: endpoint.region)
    self.transport = transport
    self.policy = policy
    self.clock = clock
    self.sleep = sleep
  }

  // MARK: - Calls

  /// Every object under `prefix` (ListObjectsV2, followed page by page), or the first `limit`.
  @concurrent
  package func list(bucket: String, prefix: String, limit: Int? = nil) async throws
    -> [S3Object]
  {
    try await listing(bucket: bucket, prefix: prefix, delimiter: nil, limit: limit).objects
  }

  /// One level under `prefix` (card 0169): its own objects and the sub-prefixes `delimiter` cuts,
  /// every page followed, so « Browse » walks a bucket without listing all of it.
  @concurrent
  package func list(bucket: String, prefix: String, delimiter: String) async throws -> S3Listing {
    try await listing(bucket: bucket, prefix: prefix, delimiter: delimiter, limit: nil)
  }

  /// The pages of a ListObjectsV2 call, gathered.
  private func listing(bucket: String, prefix: String, delimiter: String?, limit: Int?)
    async throws -> S3Listing
  {
    if let limit, limit <= 0 { return S3Listing(objects: [], prefixes: []) }
    var objects: [S3Object] = []
    var prefixes: [String] = []
    var token: String?
    repeat {
      // encoding-type=url: a key may hold characters XML 1.0 cannot carry (or normalises, \r).
      var query: [SignableRequest.QueryItem] = [
        .init("list-type", "2"), .init("prefix", prefix), .init("encoding-type", "url"),
      ]
      if let delimiter { query.append(.init("delimiter", delimiter)) }
      if let token { query.append(.init("continuation-token", token)) }
      if let limit { query.append(.init("max-keys", String(min(limit - objects.count, 1000)))) }
      let response = try await perform(
        S3Request(method: "GET", bucket: bucket, key: "", query: query))
      let page = try S3ListPage.parse(response.body)
      objects += page.objects
      prefixes += page.prefixes
      token = page.continuationToken
      if let limit, objects.count >= limit {
        return S3Listing(objects: Array(objects.prefix(limit)), prefixes: prefixes)
      }
      try Task.checkCancellation()
    } while token != nil
    return S3Listing(objects: objects, prefixes: prefixes)
  }

  /// The object at `key`, or `nil` when the service answers 404.
  @concurrent
  package func head(bucket: String, key: String) async throws -> S3Object? {
    let response: HTTPResponse
    do {
      response = try await perform(S3Request(method: "HEAD", bucket: bucket, key: key))
    } catch S3Error.service(404, _, _, _) {
      return nil
    }
    guard let size = response.headers["content-length"].flatMap({ Int64($0) }) else {
      throw S3Error.invalidResponse("HEAD \(key) without Content-Length")
    }
    return S3Object(
      key: key, size: size, etag: response.etag ?? "",
      lastModified: response.headers["last-modified"].flatMap(S3Dates.http))
  }

  /// The bytes of `key`, or of the inclusive byte `range` of it.
  @concurrent
  package func get(
    bucket: String, key: String, range: ClosedRange<Int64>?,
    progress: S3ProgressHandler? = nil
  ) async throws -> Data {
    var headers: [String: String] = [:]
    if let range { headers["range"] = "bytes=\(range.lowerBound)-\(range.upperBound)" }
    let request = S3Request(method: "GET", bucket: bucket, key: key, headers: headers)
    let response = try await perform(request, progress: progress)
    // A server that ignores Range answers 200 with the whole object: never hand that out as
    // the slice asked for.
    if range != nil, response.status != 206 {
      throw S3Error.invalidResponse("GET \(key): Range ignored (status \(response.status))")
    }
    let count = Int64(response.body.count)
    progress?(.transferred(bytes: count, total: count))
    return response.body
  }

  /// Deletes `key` (S3 answers 204 whether it existed or not).
  @concurrent
  package func delete(bucket: String, key: String) async throws {
    _ = try await perform(S3Request(method: "DELETE", bucket: bucket, key: key))
  }

  // MARK: - Plumbing

  /// Signs and sends `request` with retries; a non-2xx answer becomes `S3Error.service`.
  func perform(_ request: S3Request, progress: S3ProgressHandler? = nil) async throws
    -> HTTPResponse
  {
    try await retrying(progress) { try await send(request) }
  }

  /// One signed try of `request`; a non-2xx answer becomes `S3Error.service`.
  func send(_ request: S3Request) async throws -> HTTPResponse {
    try checked(await transport.send(prepare(request)), bucket: request.bucket)
  }

  /// `request` addressed and signed now (each try signs again: `x-amz-date` must be fresh).
  func prepare(_ request: S3Request) throws -> HTTPRequest {
    try request.prepared(endpoint: endpoint, signer: signer, date: clock())
  }

  /// Runs `body` up to `policy.tries` times while it fails retryably, backing off in between.
  func retrying<T>(_ progress: S3ProgressHandler?, _ body: () async throws -> T) async throws
    -> T
  {
    var attempt = 1
    while true {
      do {
        return try await body()
      } catch  where attempt < policy.tries && S3Error.isRetryable(error) {
        Self.logger.notice("try \(attempt) failed, retrying: \(String(describing: error))")
        progress?(.retrying(attempt: attempt, reason: String(describing: error)))
        try await sleep(policy.backoff * (1 << (attempt - 1)))
        attempt += 1
      }
    }
  }

  /// The `<Error>` document of a failed answer, status kept when the body is empty (HEAD).
  static func serviceError(_ response: HTTPResponse) -> S3Error {
    let root = response.body.isEmpty ? nil : try? XMLNode.parse(response.body)
    let error = root?.name == "Error" ? root : nil
    return .service(
      status: response.status, code: error?.text("Code"), message: error?.text("Message"),
      requestID: error?.text("RequestId") ?? response.headers["x-amz-request-id"])
  }
}
